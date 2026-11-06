#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Register an Avro schema with an optional field (union [\"null\",\"string\"]) for subject orders-value"
playground schema register --subject orders-value << 'EOF2'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "product", "type": "string"},
    {"name": "quantity", "type": "int"},
    {"name": "description", "type": ["null", "string"], "default": null}
  ]
}
EOF2

log "Produce 2 records with kafka-avro-console-producer: a union value is written {\"string\": \"...\"} (Avro JSON encoding), null as is"
playground container exec -c connect --command "kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema.id=1" << 'EOF2'
{"id": 111, "product": "foo1", "quantity": 101, "description": {"string": "my-first-command"}}
{"id": 222, "product": "foo2", "quantity": 102, "description": null}
EOF2

log "Consume the 2 records"
playground topic consume --topic orders --min-expected-messages 2 --timeout 60
