#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.transforms.yml"

log "Creating datagen source connector on topic smt-output (key set from route_field) with the Confluent Drop SMT (io.confluent.connect.transforms) nullifying the record key"
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
     "schema.keyfield": "route_field",

     "transforms": "dropKey",
     "transforms.dropKey.type": "io.confluent.connect.transforms.Drop\$Key"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Consume from smt-output and verify the Drop SMT nullified the key (route_field=ROUTE_FIELD_VALUE would otherwise be the key)"
playground topic consume --topic smt-output --min-expected-messages 10 --max-messages 10 --timeout 60 | tee /tmp/smt-drop-consume.txt

# the records really flowed and still carry route_field in the value ...
grep 'route_field":"ROUTE_FIELD_VALUE"' /tmp/smt-drop-consume.txt
# ... but the key no longer carries that value: Drop$Key nullified it (Key: label isolates the key from the value)
if grep -q "Key:ROUTE_FIELD_VALUE" /tmp/smt-drop-consume.txt
then
     logerror "Drop SMT did not nullify the key: Key:ROUTE_FIELD_VALUE is still present"
     exit 1
fi
log "Drop SMT applied: record key nullified"
