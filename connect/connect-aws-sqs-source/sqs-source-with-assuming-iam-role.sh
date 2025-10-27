#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.9.99"
then
     logwarn "minimal supported connector version is 2.0.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

export AWS_CREDENTIALS_FILE_NAME=$HOME/.aws/credentials-with-assuming-iam-role
if [ ! -f $AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "❌ $AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.with-assuming-iam-role.yml"

QUEUE_NAME=pg${USER}sqs${GITHUB_RUN_NUMBER}${TAG_BASE}
QUEUE_NAME=${QUEUE_NAME//[-._]/}

QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME --region ${AWS_REGION} --tags "cflt_managed_by=user,cflt_managed_id=$USER" | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(echo "$QUEUE_URL_RAW" | cut -d "/" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
log "Delete queue ${QUEUE_URL} in region ${AWS_REGION}"
aws sqs delete-queue --queue-url ${QUEUE_URL} --region ${AWS_REGION}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     log "Sleeping 60 seconds"
     sleep 60
     aws sqs delete-queue --queue-url ${QUEUE_URL} --region ${AWS_REGION}
fi
set -e

log "Create a FIFO queue $QUEUE_NAME in region ${AWS_REGION}"
aws sqs create-queue --queue-name $QUEUE_NAME --region ${AWS_REGION} --tags "cflt_managed_by=user,cflt_managed_id=$USER"

function cleanup_cloud_resources {
    set +e
    log "Delete SQS queue ${QUEUE_NAME} in region ${AWS_REGION}"
    check_if_continue
    aws sqs delete-queue --queue-url ${QUEUE_URL} --region ${AWS_REGION}
}
trap cleanup_cloud_resources EXIT

log "Sending messages to $QUEUE_URL"
cd ../../connect/connect-aws-sqs-source
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json --region ${AWS_REGION}
cd -

log "Creating SQS Source connector"
playground connector create-or-update --connector sqs-source  << EOF
{
     "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
     "tasks.max": "1",
     "kafka.topic": "test-sqs-source",
     "sqs.url": "$QUEUE_URL",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "errors.tolerance": "all",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF

log "Verify we have received the data in test-sqs-source topic"
playground topic consume --topic test-sqs-source --min-expected-messages 2 --timeout 60