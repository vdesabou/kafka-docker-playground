#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

verify_installed "aws"

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml"


QUEUE_NAME="sqs-source-connector-demo-ssl"
AWS_REGION=$(aws configure get region)
QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(log "$QUEUE_URL_RAW" | cut -d "/" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     log "Sleeping 60 seconds"
     sleep 60
fi
set -e

log "########"
log "##  SASL_SSL authentication"
log "########"

QUEUE_NAME="sqs-source-connector-demo-sasl-ssl"
QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(log "$QUEUE_URL_RAW" | cut -d "/" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     log "Sleeping 60 seconds"
     sleep 60
fi
set -e

log "Create a FIFO queue $QUEUE_NAME"
aws sqs create-queue --queue-name $QUEUE_NAME

log "Sending messages to $QUEUE_URL"
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json


log "Creating SQS Source connector with SASL_SSL authentication"
docker exec -e QUEUE_URL="$QUEUE_URL" connect \
     curl -X PUT \
     --cert /etc/kafka/secrets/connect.certificate.pem --key /etc/kafka/secrets/connect.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
                    "tasks.max": "1",
                    "kafka.topic": "test-sqs-source-sasl-ssl",
                    "sqs.url": "'"$QUEUE_URL"'",
                    "confluent.license": "",
                    "name": "sqs-source-sasl-ssl",
                    "confluent.topic.bootstrap.servers": "broker:9091",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
                    "confluent.topic.ssl.keystore.password" : "confluent",
                    "confluent.topic.ssl.key.password" : "confluent",
                    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "confluent.topic.ssl.truststore.password" : "confluent",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";"
          }' \
     https://localhost:8083/connectors/sqs-source/config | jq .

sleep 10

log "Verify we have received the data in test-sqs-source-sasl-ssl topic"
docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9091 --topic test-sqs-source-sasl-ssl --from-beginning --max-messages 2 --property schema.registry.url=https://schema-registry:8085 --consumer.config /etc/kafka/secrets/client_without_interceptors.config  | tail -n 3 | head -n 2 | jq .

log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}