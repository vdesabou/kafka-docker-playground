#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "7.0.99"; then
    logwarn "Schema Linking on Confluent Platform needs CP 7.1 or later"
    exit 111
fi

playground start-environment --environment mdc-plaintext --docker-compose-override-file "${PWD}/docker-compose.mdc-plaintext.yml"

log "Produce 5 Avro records to topic orders in europe: the schema is registered in schema-registry-europe"
playground topic produce --cluster europe --topic orders --nb-messages 5 << 'EOF'
{
  "type": "record",
  "namespace": "com.example",
  "name": "Order",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "amount", "type": "double"}
  ]
}
EOF
schema_id=$(playground schema get --cluster europe --subject orders-value --version latest --json | jq -r '.[0].id')
log "orders-value is schema id ${schema_id} in europe"

log "Mirror topic orders to us with Cluster Linking (the records keep their schema id ${schema_id})"
playground container exec -c broker-us --command "kafka-cluster-links --bootstrap-server broker-us:9092 --create --link europe-to-us --config bootstrap.servers=broker-europe:9092,metadata.max.age.ms=5000"
playground container exec -c broker-us --command "kafka-mirrors --create --mirror-topic orders --link europe-to-us --bootstrap-server broker-us:9092"
playground topic wait-for-records --cluster us --topic orders --min-expected-messages 5 --max-wait 120

log "Export the schemas to us with Schema Linking, into the context .europe"
playground schema exporter create --name to-europe-context --cluster europe --to us --destination-context europe
playground schema contexts --cluster us

log "The id only resolves in the context .europe: a consumer of us using the default context can't decode the records"
set +e
if playground schema get --cluster us --id "${schema_id}" > /dev/null 2>&1
then
    logerror "❌ schema id ${schema_id} should not resolve in the default context of us"
    exit 1
fi
set -e
playground schema get --cluster us --context europe --id "${schema_id}"

log "The fix: export into the default context of us instead (--context-type NONE). A destination that already has"
log "subjects (in any context) refuses it (42205 Cannot import since found existing subjects): remove the first export"
playground schema exporter pause --cluster europe --name to-europe-context
playground schema exporter delete --cluster europe --name to-europe-context
playground schema delete --cluster us --context europe --subject orders-value --permanent
playground schema exporter create --name to-default-context --cluster europe --to us --context-type NONE
playground schema compare --from europe --to us

log "Now the consumers of us decode the mirrored records"
consume_log=$(mktemp)
trap 'rm -f "$consume_log"' EXIT
set +e
playground topic consume --cluster us --topic orders --min-expected-messages 5 --timeout 60 > "$consume_log" 2>&1
ret=$?
set -e
cat "$consume_log"
if [ $ret -ne 0 ] || ! grep -q "ValueSchemaId:${schema_id}" "$consume_log"
then
    logerror "❌ the records consumed in us are not decoded with schema id ${schema_id}"
    exit 1
fi

log "Exporters of europe"
playground schema exporter list --cluster europe

log "Pause and delete the exporter (the exported schemas stay in us)"
playground schema exporter pause --cluster europe --name to-default-context
playground schema exporter delete --cluster europe --name to-default-context
