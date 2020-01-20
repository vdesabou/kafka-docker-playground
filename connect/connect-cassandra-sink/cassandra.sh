#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic topic1"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic topic1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Creating Cassandra Sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.cassandra.CassandraSinkConnector",
                    "tasks.max": "1",
                    "topics" : "topic1",
                    "cassandra.contact.points" : "cassandra",
                    "cassandra.keyspace" : "test",
                    "cassandra.consistency.level": "ONE",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "transforms": "createKey",
                    "transforms.createKey.fields": "f1",
                    "transforms.createKey.type": "org.apache.kafka.connect.transforms.ValueToKey"
          }' \
     http://localhost:8083/connectors/cassandra-sink/config | jq_docker_cli .

sleep 10

log "Verify messages are in cassandra table test.topic1"
docker exec cassandra cqlsh -e 'select * from test.topic1;'