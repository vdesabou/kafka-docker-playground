#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

# example with JSON
log "Create a topic named play-events-json"
playground topic create --topic play-events-json --nb-partitions 1
log "Produce records to play-events-json"
playground topic produce -t play-events-json --nb-messages 2 << 'EOF'
{"id": 111, "product": "foo1", "quantity": 101}
{"id": 222, "product": "foo2", "quantity": 102}
EOF

log "Create the ksqlDB streams and print the JSON output"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM playeventsjson (id INTEGER, product VARCHAR, quantity INTEGER) WITH (kafka_topic='play-events-json', value_format='json');
SELECT * FROM playeventsjson;
EOF


# example with AVRO
log "Create a topic named play-events-avro"
playground topic create --topic play-events-avro --nb-partitions 1
log "Register the Avro Schema"
playground schema register --subject play-events-avro-value << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"}]}
EOF
log "Produce records to play-events-avro"
playground topic produce -t play-events-avro --nb-messages 1 --forced-value '{"id": 111, "product": "foo1", "quantity": 101}' << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"}]}
EOF
playground topic produce -t play-events-avro --nb-messages 1 --forced-value '{"id": 222, "product": "foo2", "quantity": 102}' << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"}]}
EOF

log "Create the ksqlDB streams and print the AVRO output"
playground ksqldb sql << EOF
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
playground topic create --topic play-events-proto --nb-partitions 1
log "Produce Protobuf records"
playground topic produce -t play-events-proto --nb-messages 1 --forced-value '{"id": 111, "product": "foo1", "quantity": 500}' << 'EOF'
syntax = "proto3"; message MyRecord { int32 id = 1; string product = 2; int32 quantity = 3;}
EOF
playground topic produce -t play-events-proto --nb-messages 1 --forced-value '{"id": 222, "product": "foo2", "quantity": 500}' << 'EOF'
syntax = "proto3"; message MyRecord { int32 id = 1; string product = 2; int32 quantity = 3;}
EOF

log "Create the ksqlDB streams and print the PROTOBUF output"
playground ksqldb sql << EOF
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
playground topic create --topic play-events-json-sr --nb-partitions 1
log "Produce JSON_SR records"
playground topic produce -t play-events-json-sr --nb-messages 1 --forced-value '{"id": 111, "product": "foo1", "quantity": 500}' << 'EOF'
{"type":"object", "properties":{"id":{"type":"number"},"product":{"type":"string"},"amount":{"type":"number"} }}
EOF
playground topic produce -t play-events-json-sr --nb-messages 1 --forced-value '{"id": 222, "product": "foo2", "quantity": 501}' << 'EOF'
{"type":"object", "properties":{"id":{"type":"number"},"product":{"type":"string"},"amount":{"type":"number"} }}
EOF
playground topic produce -t play-events-json-sr --nb-messages 1 --forced-value '{"id": 333, "product": "foo3", "quantity": 502}' << 'EOF'
{"type":"object", "properties":{"id":{"type":"number"},"product":{"type":"string"},"amount":{"type":"number"} }}
EOF

log "Create the ksqlDB streams and print the JSON_SR output"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM playeventsjsonsr
  WITH (
    KAFKA_TOPIC='play-events-json-sr',
    VALUE_FORMAT='JSON_SR'
  );
SELECT * FROM playeventsjsonsr;
EOF
