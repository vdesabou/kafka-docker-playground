#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.yml"

log "Creating datagen source connector on topic smt-output with the Apache InsertHeader SMT (org.apache.kafka.connect.transforms) adding a static header"
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

     "transforms": "insertHeader",
     "transforms.insertHeader.type": "org.apache.kafka.connect.transforms.InsertHeader",
     "transforms.insertHeader.header": "smt_test_header",
     "transforms.insertHeader.value.literal": "INSERTED_HEADER_VALUE"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Consume from smt-output and verify the InsertHeader SMT added the smt_test_header header (INSERTED_HEADER_VALUE)"
playground topic consume --topic smt-output --min-expected-messages 10 --max-messages 10 --timeout 60 | tee /tmp/smt-insertheader-consume.txt

grep "INSERTED_HEADER_VALUE" /tmp/smt-insertheader-consume.txt
log "InsertHeader SMT applied: smt_test_header header present"
