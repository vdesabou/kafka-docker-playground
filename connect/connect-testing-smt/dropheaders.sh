#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.yml"

log "Creating datagen source connector on topic smt-output: two InsertHeader SMTs add a keep_header and a drop_header, then the Apache DropHeaders SMT (org.apache.kafka.connect.transforms) removes drop_header"
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

     "transforms": "insertKeep,insertDrop,dropHeaders",
     "transforms.insertKeep.type": "org.apache.kafka.connect.transforms.InsertHeader",
     "transforms.insertKeep.header": "keep_header",
     "transforms.insertKeep.value.literal": "KEEP_HEADER_VALUE",
     "transforms.insertDrop.type": "org.apache.kafka.connect.transforms.InsertHeader",
     "transforms.insertDrop.header": "drop_header",
     "transforms.insertDrop.value.literal": "DROP_HEADER_VALUE",
     "transforms.dropHeaders.type": "org.apache.kafka.connect.transforms.DropHeaders",
     "transforms.dropHeaders.headers": "drop_header"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Consume from smt-output and verify DropHeaders kept keep_header (KEEP_HEADER_VALUE) and removed drop_header (DROP_HEADER_VALUE)"
playground topic consume --topic smt-output --min-expected-messages 10 --max-messages 10 --timeout 60 | tee /tmp/smt-dropheaders-consume.txt

grep "KEEP_HEADER_VALUE" /tmp/smt-dropheaders-consume.txt
if grep -q "DROP_HEADER_VALUE" /tmp/smt-dropheaders-consume.txt
then
     logerror "DropHeaders SMT did not remove drop_header: DROP_HEADER_VALUE is still present"
     exit 1
fi
log "DropHeaders SMT applied: keep_header present and drop_header removed"
