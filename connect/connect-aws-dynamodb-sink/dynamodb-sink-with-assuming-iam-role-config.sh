#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.2.99"
then
    logwarn "connector version >= 1.3.0 do not support CP versions < 6.0.0"
    exit 111
fi

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.4.99"
then
     logwarn "minimal supported connector version is 1.5.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

AWS_STS_ROLE_ARN=${AWS_STS_ROLE_ARN:-$1}

if [ -z "$AWS_STS_ROLE_ARN" ]
then
     logerror "AWS_STS_ROLE_ARN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID" ]
then
     logerror "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY" ]
then
     logerror "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

handle_aws_credentials

DYNAMODB_TABLE="pg${USER}dynamo${TAG}"
DYNAMODB_ENDPOINT="https://dynamodb.$AWS_REGION.amazonaws.com"

set +e
aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region $AWS_REGION --query 'Table.TableStatus' --output text 2>/dev/null
if [ $? -eq 0 ]
then
  log "Delete table, this might fail"
  aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION
  while true; do
      aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region $AWS_REGION --query 'Table.TableStatus' --output text 2>/dev/null
      if [ $? -ne 0 ]
      then
          break
      fi
      sleep 5
  done
fi
set -e

log "Create dynamodb table $DYNAMODB_TABLE"
aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=f1,AttributeType=S AttributeName=offset,AttributeType=N \
    --key-schema AttributeName=f1,KeyType=HASH AttributeName=offset,KeyType=RANGE \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --endpoint-url https://dynamodb.$AWS_REGION.amazonaws.com \
    --tags Key=cflt_managed_by,Value=user Key=cflt_managed_id,Value="$USER"

log "Waiting for table to be created"
while true
do
    table_status=$(aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region $AWS_REGION --query 'Table.TableStatus' --output text)
    if [ "$table_status" == "ACTIVE" ]
    then
        break
    fi
    sleep 5
done

function cleanup_cloud_resources {
    set +e
    log "Delete table $DYNAMODB_TABLE"
    check_if_continue
    aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION
}
trap cleanup_cloud_resources EXIT

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.with-assuming-iam-role-config.yml"

log "Sending messages to topic $DYNAMODB_TABLE"
playground topic produce -t $DYNAMODB_TABLE --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Creating AWS DynamoDB Sink connector"
playground connector create-or-update --connector dynamodb-sink  << EOF
{
    "connector.class": "io.confluent.connect.aws.dynamodb.DynamoDbSinkConnector",
    "tasks.max": "1",
    "topics": "$DYNAMODB_TABLE",
    "aws.dynamodb.region": "$AWS_REGION",
    "aws.dynamodb.endpoint": "$DYNAMODB_ENDPOINT",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "aws.dynamodb.credentials.provider.class": "io.confluent.connect.aws.dynamodb.auth.AwsAssumeRoleCredentialsProvider",
    "aws.dynamodb.credentials.provider.sts.role.arn": "$AWS_STS_ROLE_ARN",
    "aws.dynamodb.credentials.provider.sts.role.session.name": "session-name",
    "aws.dynamodb.credentials.provider.sts.role.external.id": "123"
}
EOF

sleep 10

playground connector show-lag --max-wait 300

log "Verify data is in DynamoDB"
aws dynamodb scan --table-name $DYNAMODB_TABLE --region $AWS_REGION  > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log
