#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
${DIR}/../WaitForConnectAndControlCenter.sh

QUEUE_NAME="sqs-source-connector-demo"
AWS_REGION=$(aws configure get region)
QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(echo "$QUEUE_URL_RAW" | cut -d "/" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
echo "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     echo "Sleeping 60 seconds"
     sleep 60
fi
set -e

echo "Create a FIFO queue $QUEUE_NAME"
aws sqs create-queue --queue-name $QUEUE_NAME

echo "Sending messages to $QUEUE_URL"
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json

echo "Creating SQS Source connector"
docker container exec -e QUEUE_URL="$QUEUE_URL" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "sqs-source",
        "config": {
               "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "test-sqs-source",
               "sqs.url": "'"$QUEUE_URL"'",
               "confluent.license": "",
               "name": "sqs-source",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

echo "Verify we have received the data in test-sqs-source topic"
docker container exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic test-sqs-source --from-beginning --max-messages 2

echo "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}