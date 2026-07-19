#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.yml"

log "Creating datagen source connector on topic smt-output with the Apache RegexRouter SMT (org.apache.kafka.connect.transforms) rewriting the target topic to smt-output-transformed"
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

     "transforms": "regexRouter",
     "transforms.regexRouter.type": "org.apache.kafka.connect.transforms.RegexRouter",
     "transforms.regexRouter.regex": "smt-output",
     "transforms.regexRouter.replacement": "smt-output-transformed"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Consume from the renamed topic smt-output-transformed and verify the RegexRouter SMT routed the records there"
playground topic consume --topic smt-output-transformed --min-expected-messages 10 --max-messages 10 --timeout 60
log "RegexRouter SMT applied: records routed to smt-output-transformed"
