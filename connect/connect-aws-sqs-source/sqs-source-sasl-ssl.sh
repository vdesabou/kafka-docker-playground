#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml"

QUEUE_NAME=pg${USER}sqs${TAG}
QUEUE_NAME=${QUEUE_NAME//[-._]/}
AWS_REGION=$(aws configure get region | tr '\r' '\n')
QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(echo "$QUEUE_URL_RAW" | cut -d "/" -f 4)
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

log "Create a FIFO queue $QUEUE_NAME"
aws sqs create-queue --queue-name $QUEUE_NAME

log "Sending messages to $QUEUE_URL"
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json


log "Creating SQS Source connector with SASL_SSL authentication"
curl -X PUT \
     --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "test-sqs-source-sasl-ssl",
               "sqs.url": "'"$QUEUE_URL"'",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
               "confluent.topic.ssl.keystore.password" : "confluent",
               "confluent.topic.ssl.key.password" : "confluent",
               "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
               "confluent.topic.ssl.truststore.password" : "confluent",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.sasl.mechanism": "PLAIN",
               "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     https://localhost:8083/connectors/sqs-source-sasl-ssl/config | jq .

sleep 10

log "Verify we have received the data in test-sqs-source-sasl-ssl topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --topic test-sqs-source-sasl-ssl --from-beginning --max-messages 2 --property schema.registry.url=https://schema-registry:8081 --consumer.config /etc/kafka/secrets/client_without_interceptors.config  | tail -n 3 | head -n 2

log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
