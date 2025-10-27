#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.2.99"
then
    logwarn "connector version >= 1.3.0 do not support CP versions < 6.0.0"
    exit 111
fi

handle_aws_credentials

DYNAMODB_TABLE="pg${USER}fmdynamo${GITHUB_RUN_NUMBER}${TAG_BASE}"

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

bootstrap_ccloud_environment "aws" "$AWS_REGION"

set +e
playground topic delete --topic $DYNAMODB_TABLE
sleep 3
playground topic create --topic $DYNAMODB_TABLE --nb-partitions 1
set -e

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

connector_name="DynamoDbSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating AWS DynamoDB sink connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "DynamoDbSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "input.data.format": "AVRO",
    "topics": "$DYNAMODB_TABLE",
    "aws.dynamodb.endpoint": "https://dynamodb.$AWS_REGION.amazonaws.com",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

playground connector show-lag --max-wait 300 --connector $connector_name

log "Verify data is in DynamoDB"
aws dynamodb scan --table-name $DYNAMODB_TABLE --region $AWS_REGION  > /tmp/result.log  2>&1
cat /tmp/result.log
grep "first_name" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name