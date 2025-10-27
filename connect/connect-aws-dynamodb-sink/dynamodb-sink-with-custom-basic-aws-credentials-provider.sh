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
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

logwarn "⚠️ This example and associated custom code is not supported, use at your own risks !"

for component in basicawscredentialsprovider
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "❌ failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

handle_aws_credentials

DYNAMODB_TABLE="pg${USER}dynamo${GITHUB_RUN_NUMBER}${TAG}"
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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.with-custom-basic-aws-credentials-provider.yml"

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
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "aws.dynamodb.credentials.provider.class": "com.github.vdesabou.BasicAwsCredentialsProvider",
    "aws.dynamodb.credentials.provider.aws.access.key.id": "$AWS_ACCESS_KEY_ID",
    "aws.dynamodb.credentials.provider.aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY"
}
EOF

sleep 10

playground connector show-lag --max-wait 300

log "Verify data is in DynamoDB"
aws dynamodb scan --table-name $DYNAMODB_TABLE --region $AWS_REGION  > /tmp/result.log  2>&1
cat /tmp/result.log
grep "first_name" /tmp/result.log