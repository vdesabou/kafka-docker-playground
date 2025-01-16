#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.2.99"
then
    logwarn "WARN: connector version >= 1.3.0 do not support CP versions < 6.0.0"
    exit 111
fi

export AWS_CREDENTIALS_FILE_NAME=$HOME/.aws/credentials-with-assuming-iam-role
if [ ! -f $AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

handle_aws_credentials

DYNAMODB_TABLE="pg${USER}dynamo${TAG}"
DYNAMODB_ENDPOINT="https://dynamodb.$AWS_REGION.amazonaws.com"

set +e
log "Delete table, this might fail"
aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION
set -e

function cleanup_cloud_resources {
    set +e
    log "Delete table $DYNAMODB_TABLE"
    check_if_continue
    aws dynamodb delete-table --table-name $DYNAMODB_TABLE --region $AWS_REGION
}
trap cleanup_cloud_resources EXIT

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.with-assuming-iam-role.yml"

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
     "confluent.topic.replication.factor": "1"
}
EOF

log "Sleeping 120 seconds, waiting for table to be created"
sleep 120

log "Verify data is in DynamoDB"
aws dynamodb scan --table-name $DYNAMODB_TABLE --region $AWS_REGION  > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log