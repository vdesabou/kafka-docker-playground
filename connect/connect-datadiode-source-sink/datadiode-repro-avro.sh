#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"
fi

log "Creating DataDiode Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.diode.source.DataDiodeSourceConnector",
               "kafka.topic.prefix": "dest_",
               "key.converter":"org.apache.kafka.connect.converters.ByteArrayConverter",
               "value.converter":"org.apache.kafka.connect.converters.ByteArrayConverter",
               "header.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "diode.port": "3456",
               "diode.encryption.password": "supersecretpassword",
               "diode.encryption.salt": "secretsalt",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/datadiode-source/config | jq .

log "Creating DataDiode Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.diode.sink.DataDiodeSinkConnector",
               "tasks.max": "1",
               "topics": "diode",
               "key.converter":"org.apache.kafka.connect.converters.ByteArrayConverter",
               "value.converter":"org.apache.kafka.connect.converters.ByteArrayConverter",
               "header.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "diode.host": "connect",
               "diode.port": "3456",
               "diode.encryption.password": "supersecretpassword",
               "diode.encryption.salt": "secretsalt",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/datadiode-sink/config | jq .

sleep 10

log "Send message to diode topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic diode --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 5

log "Verifying topic dest_diode"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dest_diode --from-beginning --max-messages 5
