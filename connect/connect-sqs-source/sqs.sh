#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "aws"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


QUEUE_NAME="sqs-source-connector-demo"
AWS_REGION=$(aws configure get region)
QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(echo -e "\033[0;33m$QUEUE_URL_RAW" | cut -d "/\033[0m" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
echo -e "\033[0;33mDelete queue ${QUEUE_URL}\033[0m"
aws sqs delete-queue --queue-url ${QUEUE_URL}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     echo -e "\033[0;33mSleeping 60 seconds\033[0m"
     sleep 60
fi
set -e

echo -e "\033[0;33mCreate a FIFO queue $QUEUE_NAME\033[0m"
aws sqs create-queue --queue-name $QUEUE_NAME

echo -e "\033[0;33mSending messages to $QUEUE_URL\033[0m"
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json

echo -e "\033[0;33mCreating SQS Source connector\033[0m"
docker exec -e QUEUE_URL="$QUEUE_URL" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "test-sqs-source",
               "sqs.url": "'"$QUEUE_URL"'",
               "confluent.license": "",
               "name": "sqs-source",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sqs-source/config | jq .

echo -e "\033[0;33mVerify we have received the data in test-sqs-source topic\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic test-sqs-source --from-beginning --max-messages 2

echo -e "\033[0;33mDelete queue ${QUEUE_URL}\033[0m"
aws sqs delete-queue --queue-url ${QUEUE_URL}