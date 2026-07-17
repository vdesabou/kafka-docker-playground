#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.transforms.yml"

log "Creating datagen source connector on topic smt-output with the Confluent ExtractTopic SMT (io.confluent.connect.transforms) routing records to a topic named after the route_field value (ROUTE_FIELD_VALUE)"
playground connector create-or-update --connector datagen-smt-output  << EOF
{
     "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
     "kafka.topic": "smt-output",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "max.interval": 100,
     "iterations": "10",
     "tasks.max": "1",
     "schema.filename": "/tmp/schemas/smt-source.avro",

     "transforms": "extractTopic",
     "transforms.extractTopic.type": "io.confluent.connect.transforms.ExtractTopic\$Value",
     "transforms.extractTopic.field": "route_field",
     "transforms.extractTopic.field.format": "PLAIN",
     "transforms.extractTopic.skip.missing.or.null": "false"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Consume from topic ROUTE_FIELD_VALUE and verify the ExtractTopic SMT routed the records to the topic named after the route_field value"
playground topic consume --topic ROUTE_FIELD_VALUE --min-expected-messages 10 --max-messages 10 --timeout 60
log "ExtractTopic SMT applied: records routed to the ROUTE_FIELD_VALUE topic"
