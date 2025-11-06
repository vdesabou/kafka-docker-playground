#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.2.99"
then
    logwarn "connector version >= 1.3.0 do not support CP versions < 6.0.0"
    exit 111
fi

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.4.99"
then
     logwarn "minimal supported connector version is 1.5.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.proxy.yml"

DYNAMODB_TABLE="pg${USER}dynamo${GITHUB_RUN_NUMBER}${TAG_BASE}"
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
    --attribute-definitions AttributeName=first_name,AttributeType=S AttributeName=last_name,AttributeType=S \
    --key-schema AttributeName=first_name,KeyType=HASH AttributeName=last_name,KeyType=RANGE \
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

log "Sending messages to topic $DYNAMODB_TABLE"
playground topic produce -t $DYNAMODB_TABLE --nb-messages 10 << 'EOF'
{
  "fields": [
    {
      "name": "first_name",
      "type": "string"
    },
    {
      "name": "last_name",
      "type": "string"
    }
  ],
  "name": "Customer",
  "namespace": "com.github.vdesabou",
  "type": "record"
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
    "aws.dynamodb.proxy.url": "http://nginx-proxy:8888",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

sleep 10

playground connector show-lag --max-wait 300

log "Verify data is in DynamoDB"
aws dynamodb scan --table-name $DYNAMODB_TABLE --region $AWS_REGION  > /tmp/result.log  2>&1
cat /tmp/result.log
grep "first_name" /tmp/result.log