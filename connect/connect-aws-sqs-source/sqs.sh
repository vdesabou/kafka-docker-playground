#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ ! -f $HOME/.aws/credentials ]
then
     logerror "ERROR: $HOME/.aws/credentials is not set"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

QUEUE_NAME="sqs-source-connector-demo"
AWS_REGION=$(aws_docker_cli configure get region | tr '\r' '\n')
QUEUE_URL_RAW=$(aws_docker_cli sqs create-queue --queue-name $QUEUE_NAME | jq_docker_cli .QueueUrl)
AWS_ACCOUNT_NUMBER=$(echo "$QUEUE_URL_RAW" | cut -d "/" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
log "Delete queue ${QUEUE_URL}"
aws_docker_cli sqs delete-queue --queue-url ${QUEUE_URL}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     log "Sleeping 60 seconds"
     sleep 60
fi
set -e

log "Create a FIFO queue $QUEUE_NAME"
aws_docker_cli sqs create-queue --queue-name $QUEUE_NAME

log "Sending messages to $QUEUE_URL"
aws_docker_cli sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json

log "Creating SQS Source connector"
docker exec -e QUEUE_URL="$QUEUE_URL" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "test-sqs-source",
               "sqs.url": "'"$QUEUE_URL"'",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sqs-source/config | jq_docker_cli .

log "Verify we have received the data in test-sqs-source topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-sqs-source --from-beginning --max-messages 2

log "Delete queue ${QUEUE_URL}"
aws_docker_cli sqs delete-queue --queue-url ${QUEUE_URL}