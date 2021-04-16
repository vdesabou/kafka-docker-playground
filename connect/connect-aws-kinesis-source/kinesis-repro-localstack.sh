#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# This is required even though we use a local instance !
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

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

# rm -f *.jks
# # Create truststore and import the CA cert
# docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG}  keytool -noprompt -keystore /tmp/my.truststore.jks -alias CARoot -import -file /tmp/server-crt.pem -storepass confluent -keypass confluent
# docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -noprompt -destkeystore /tmp/my.truststore.jks -importkeystore -srckeystore /usr/lib/jvm/zulu11-ca/lib/security/cacerts -srcstorepass changeit -deststorepass confluent


# docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} openssl pkcs12 -export -in /tmp/server-crt.pem -inkey /tmp/server-key.pem \
#                -out /tmp/kinesis-server.p12 -name kinesis-server \
#                -CAfile /tmp/ca-crt.pem -caname CARoot -passout pass:confluent

# docker run --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} keytool -importkeystore \
#         -deststorepass confluent -destkeypass confluent -destkeystore /tmp/my.trustore.jks \
#         -srckeystore /tmp/kinesis-server.p12 -srcstoretype PKCS12 -srcstorepass confluent \
#         -alias kinesis-server

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-localstack.yml"

KINESIS_STREAM_NAME=my_kinesis_stream$TAG
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME//[-.]/}

log "Create a Kinesis stream $KINESIS_STREAM_NAME"
/usr/local/bin/aws kinesis --endpoint-url https://localhost:4566/ create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1 --no-verify-ssl

log "Sleep 10 seconds to let the Kinesis stream being fully started"
sleep 10

AWS_REGION=$(aws configure get region | tr '\r' '\n')
TODAY=$(date +%s)
log "Creating Kinesis Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.base.url": "https://kinesis-local:4566",
               "kinesis.stream": "'"$KINESIS_STREAM_NAME"'",
               "kinesis.region": "'"$AWS_REGION"'",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source-local/config | jq .

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into my_kinesis_stream.
/usr/local/bin/aws kinesis --endpoint-url https://localhost:4566/ put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1 --no-verify-ssl

sleep 10

log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
/usr/local/bin/aws kinesis --endpoint-url https://localhost:4566/ delete-stream --stream-name $KINESIS_STREAM_NAME --no-verify-ssl