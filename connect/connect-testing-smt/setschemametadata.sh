#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.datagen.yml"

log "Creating datagen source connector on topic smt-output (Avro value + Schema Registry) with the Apache SetSchemaMetadata SMT (org.apache.kafka.connect.transforms) overriding the value schema name/version"
playground connector create-or-update --connector datagen-smt-output  << EOF
{
     "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
     "kafka.topic": "smt-output",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "max.interval": 100,
     "iterations": "10",
     "tasks.max": "1",
     "schema.filename": "/tmp/schemas/smt-source.avro",

     "transforms": "setSchemaMetadata",
     "transforms.setSchemaMetadata.type": "org.apache.kafka.connect.transforms.SetSchemaMetadata\$Value",
     "transforms.setSchemaMetadata.schema.name": "com.confluent.smttest.SchemaMetadataApplied",
     "transforms.setSchemaMetadata.schema.version": "2"
}
EOF

wait_for_datagen_connector_to_inject_data "smt-output" "1"

log "Fetch the registered value schema for subject smt-output-value and verify the SetSchemaMetadata SMT set the record name (datagen's original schema name is SmtSource)"
playground schema get --subject smt-output-value | tee /tmp/smt-setschemametadata-schema.txt

grep "SchemaMetadataApplied" /tmp/smt-setschemametadata-schema.txt
if grep -q '"name" *: *"SmtSource"' /tmp/smt-setschemametadata-schema.txt
then
     logerror "SetSchemaMetadata SMT did not override the schema name: original SmtSource is still present"
     exit 1
fi
log "SetSchemaMetadata SMT applied: value schema name overridden to com.confluent.smttest.SchemaMetadataApplied"
