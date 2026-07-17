#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.yml"

log "Creating datagen source connector on topic smt-output with the Apache HeaderFrom SMT (org.apache.kafka.connect.transforms) moving route_field into a header"
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

     "transforms": "headerFrom",
     "transforms.headerFrom.type": "org.apache.kafka.connect.transforms.HeaderFrom\$Value",
     "transforms.headerFrom.fields": "route_field",
     "transforms.headerFrom.headers": "moved_header",
     "transforms.headerFrom.operation": "move"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Consume from smt-output and verify the HeaderFrom SMT moved route_field (ROUTE_FIELD_VALUE) into the moved_header header"
playground topic consume --topic smt-output --min-expected-messages 10 --max-messages 10 --timeout 60 | tee /tmp/smt-headerfrom-consume.txt

# operation=move removes route_field from the value, so ROUTE_FIELD_VALUE now appears only in the header
grep "moved_header:ROUTE_FIELD_VALUE" /tmp/smt-headerfrom-consume.txt
log "HeaderFrom SMT applied: route_field moved into the moved_header header"
