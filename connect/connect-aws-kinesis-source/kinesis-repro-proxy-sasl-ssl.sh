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

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.plaintext-repro-proxy.yml"

set +e
log "Delete the stream"
aws kinesis delete-stream --stream-name my_kinesis_stream
set -e

sleep 5

log "Create a Kinesis stream my_kinesis_stream"
aws kinesis create-stream --stream-name my_kinesis_stream --shard-count 1

log "Sleep 60 seconds to let the Kinesis stream being fully started"
sleep 60

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into my_kinesis_stream.
aws kinesis put-record --stream-name my_kinesis_stream --partition-key 123 --data test-message-1


log "Creating Kinesis Source connector"
docker exec connect curl -X PUT \
     --cert /etc/kafka/secrets/connect.certificate.pem --key /etc/kafka/secrets/connect.key --tlsv1.2 --cacert /etc/kafka/secrets/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.region": "EU_WEST_3",
               "kinesis.stream": "my_kinesis_stream",
               "kinesis.proxy.url": "https://nginx_proxy:8888",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
               "confluent.topic.ssl.keystore.password" : "confluent",
               "confluent.topic.ssl.key.password" : "confluent",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.sasl.mechanism": "PLAIN",
               "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";"
          }' \
     https://localhost:8083/connectors/kinesis-source/config | jq .

log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --consumer.config /etc/kafka/secrets/client_without_interceptors.config --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
aws kinesis delete-stream --stream-name my_kinesis_stream