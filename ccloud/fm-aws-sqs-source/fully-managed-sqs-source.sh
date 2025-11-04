#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

handle_aws_credentials

bootstrap_ccloud_environment "aws" "$AWS_REGION"

set +e
playground topic delete --topic test-sqs-source
sleep 3
playground topic create --topic test-sqs-source --nb-partitions 1
set -e

QUEUE_NAME=pg${USER}fmsqs${GITHUB_RUN_NUMBER}${TAG_BASE}
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
cd ../../ccloud/fm-aws-sqs-source
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json --region ${AWS_REGION}
cd -

connector_name="SqsSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "SqsSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "kafka.topic": "test-sqs-source",
    "sqs.url": "$QUEUE_URL",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY",
    "output.data.format": "JSON",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify we have received the data in test-sqs-source topic"
playground topic consume --topic test-sqs-source --min-expected-messages 2 --timeout 60

log "Asserting that SQS queue is empty after connector processing"
QUEUE_ATTRIBUTES=$(aws sqs get-queue-attributes \
    --queue-url $QUEUE_URL \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --region ${AWS_REGION} \
    --query "Attributes" \
    --output json)

VISIBLE_MESSAGES=$(echo "$QUEUE_ATTRIBUTES" | jq -r '.ApproximateNumberOfMessages // "0" | tonumber')
IN_FLIGHT_MESSAGES=$(echo "$QUEUE_ATTRIBUTES" | jq -r '.ApproximateNumberOfMessagesNotVisible // "0" | tonumber')
TOTAL_MESSAGES=$((VISIBLE_MESSAGES + IN_FLIGHT_MESSAGES))

log "Queue message count - Visible: $VISIBLE_MESSAGES, In-flight: $IN_FLIGHT_MESSAGES, Total: $TOTAL_MESSAGES"

if [ "$TOTAL_MESSAGES" -eq 0 ]; then
    log "✅ SUCCESS: SQS queue is empty - commitRecord API working correctly"
else
    log "❌ FAILURE: $TOTAL_MESSAGES messages still remain in SQS queue (Visible: $VISIBLE_MESSAGES, In-flight: $IN_FLIGHT_MESSAGES)"
    exit 1
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name