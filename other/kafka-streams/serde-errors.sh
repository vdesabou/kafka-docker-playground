#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/streams-functions.bash

# Avro with Schema Registry: a poison pill (deserialization exception handler), a record too large for the producer
# (production exception handler), schema evolution, and the default LogAndFailExceptionHandler stopping an application
started_at=$(now)
start_streams_scenario serde-errors

# produces payment $1 (key) with Avro value $2, the schema on stdin
function produce_payment () {
    playground topic produce --topic payments --nb-messages 1 --key "$1" --forced-value "$2" > /dev/null
}

log "💳 Payments p1 and p2, Avro schema v1 (id, amount)"
produce_payment p1 '{"id":"p1","amount":10.5}' << 'EOF2'
{"type":"record","name":"Payment","namespace":"io.confluent.playground","fields":[{"name":"id","type":"string"},{"name":"amount","type":"double"}]}
EOF2
produce_payment p2 '{"id":"p2","amount":20.0}' << 'EOF2'
{"type":"record","name":"Payment","namespace":"io.confluent.playground","fields":[{"name":"id","type":"string"},{"name":"amount","type":"double"}]}
EOF2

log "☠️ A poison pill: a record that is not Avro (no magic byte, no schema id)"
playground topic produce --topic payments --nb-messages 1 --key poison --value "this is not avro" --value-format raw > /dev/null

log "🧬 Schema evolution: payment p3 with schema v2, which adds currency (default EUR): backward compatible, read with its own (writer) schema"
produce_payment p3 '{"id":"p3","amount":30.0,"currency":"USD"}' << 'EOF2'
{"type":"record","name":"Payment","namespace":"io.confluent.playground","fields":[{"name":"id","type":"string"},{"name":"amount","type":"double"},{"name":"currency","type":"string","default":"EUR"}]}
EOF2

log "🎈 Payment inflate: the application turns it into a value larger than producer.max.request.size (4096)"
produce_payment inflate '{"id":"inflate","amount":1.0}' << 'EOF2'
{"type":"record","name":"Payment","namespace":"io.confluent.playground","fields":[{"name":"id","type":"string"},{"name":"amount","type":"double"}]}
EOF2

wait_for_records payments-processed '(map(.key) | sort) == ["p1","p2","p3"] and (map(select(.key == "p3"))[0].value.currency == "USD")' "p1, p2 and p3 processed (p3 with its currency), the poison pill and inflate skipped"

log "🩹 default.deserialization.exception.handler=LogAndContinueExceptionHandler: the poison pill is logged and skipped"
wait_for_log_since "$started_at" "Exception caught during Deserialization" streams streams2 streams3

log "📦 default.production.exception.handler=ContinueOnRecordTooLargeHandler: the RecordTooLargeException of inflate is logged and skipped"
wait_for_log_since "$started_at" "Production exception handler: skipping" streams streams2 streams3

log "💥 fail-on-poison-pill: the same topology with the default LogAndFailExceptionHandler stops on the poison pill (state ERROR)"
wait_for_log_since "$started_at" "fail-on-poison-pill state transition from PENDING_ERROR to ERROR" streams streams2 streams3
wait_for_log_since "$started_at" "Uncaught exception in a stream thread of streams-serde-errors-fail-on-poison-pill" streams streams2 streams3

