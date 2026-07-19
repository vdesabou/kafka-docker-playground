#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.yml"

log "Creating datagen source connector on topic smt-output with the Apache ValueToKey SMT (org.apache.kafka.connect.transforms) forming the key from the route_field value field"
playground connector create-or-update --connector datagen-smt-output  << EOF
{
     "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
     "kafka.topic": "smt-output",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "key.converter.schemas.enable": "false",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "max.interval": 100,
     "iterations": "10",
     "tasks.max": "1",
     "schema.filename": "/tmp/schemas/smt-source.avro",

     "transforms": "valueToKey",
     "transforms.valueToKey.type": "org.apache.kafka.connect.transforms.ValueToKey",
     "transforms.valueToKey.fields": "route_field"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Consume from smt-output and verify the ValueToKey SMT built the record key from route_field"
playground topic consume --topic smt-output --min-expected-messages 10 --max-messages 10 --timeout 60 | tee /tmp/smt-valuetokey-consume.txt

# the leading { isolates the key {"route_field":"ROUTE_FIELD_VALUE"} from the value where route_field is preceded by a comma
grep '{"route_field":"ROUTE_FIELD_VALUE"}' /tmp/smt-valuetokey-consume.txt
log "ValueToKey SMT applied: record key built from route_field"
