#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

# example with JSON
log "Create a topic named play-events-json"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic play-events-json --partitions 1
log "Produce records to play-events-json"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic play-events-json << EOF
{"id": 111, "product": "foo1", "quantity": 101}
{"id": 222, "product": "foo2", "quantity": 102}
EOF

log "Create the ksqlDB streams and print the JSON output"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM playeventsjson (id INTEGER, product VARCHAR, quantity INTEGER) WITH (kafka_topic='play-events-json', value_format='json');
SELECT * FROM playeventsjson;
EOF


# example with AVRO
log "Create a topic named play-events-avro"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic play-events-avro --partitions 1
log "Register the Avro Schema"
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" -X POST http://schema-registry:8081/subjects/play-events-avro-value/versions --data '{"schema":"{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"}]}"}'
log "Produce records to play-events-avro"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic play-events-avro --property value.schema.id=1 << EOF
{"id": 111, "product": "foo1", "quantity": 101}
{"id": 222, "product": "foo2", "quantity": 102}
EOF

log "Create the ksqlDB streams and print the AVRO output"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM playeventsavro
  WITH (
    KAFKA_TOPIC='play-events-avro',
    VALUE_FORMAT='AVRO'
  );
SELECT * FROM playeventsavro;
EOF


# example with PROTOBUF
log "Create a topic named play-events-proto"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic play-events-proto --partitions 1
log "Produce Protobuf records"
docker exec -i connect kafka-protobuf-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic play-events-proto --property value.schema='syntax = "proto3"; message MyRecord { int32 id = 1; string product = 2; int32 quantity = 3;}' << EOF
{"id": 111, "product": "foo1", "quantity": 500}
{"id": 222, "product": "foo2", "quantity": 500}
EOF

log "Create the ksqlDB streams and print the PROTOBUF output"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM playeventsproto
  WITH (
    KAFKA_TOPIC='play-events-proto',
    VALUE_FORMAT='PROTOBUF'
  );
SELECT * FROM playeventsproto;
EOF

# example with JSON_SR
log "Create a topic named play-events-json-sr"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic play-events-json-sr --partitions 1
log "Produce JSON_SR records"
docker exec -i connect kafka-json-schema-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic play-events-json-sr --property value.schema='{"type":"object", "properties":{"id":{"type":"number"},"product":{"type":"string"},"amount":{"type":"number"} }}' << EOF
{"id": 111, "product": "foo1", "quantity": 500}
{"id": 222, "product": "foo2", "quantity": 501}
{"id": 333, "product": "foo3", "quantity": 502}
EOF

log "Create the ksqlDB streams and print the JSON_SR output"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM playeventsjsonsr
  WITH (
    KAFKA_TOPIC='play-events-json-sr',
    VALUE_FORMAT='JSON_SR'
  );
SELECT * FROM playeventsjsonsr;
EOF
