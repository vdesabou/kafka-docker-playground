#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# the Kafka Streams application of other/kafka-streams, scenario serde-errors: two applications read the Avro payments,
# streams-serde-errors (LogAndContinueExceptionHandler) and streams-serde-errors-fail-on-poison-pill (the default,
# LogAndFailExceptionHandler)
cd "${DIR}/../../other/kafka-streams"
DIR="$PWD"
source "${DIR}/streams-functions.bash"
started_at=$(now)
start_streams_scenario serde-errors

function produce_payment () {
    playground topic produce --topic payments --nb-messages 1 --key "$1" --forced-value "$2" > /dev/null << 'EOF2'
{"type":"record","name":"Payment","namespace":"io.confluent.playground","fields":[{"name":"id","type":"string"},{"name":"amount","type":"double"}]}
EOF2
}

log "💳 Payments p1 and p2"
produce_payment p1 '{"id":"p1","amount":10.5}'
produce_payment p2 '{"id":"p2","amount":20.0}'

# 💥 a test tool of another team writes a plain text record to the topic
log "🧪 10:02: a test tool sends something to payments"
playground topic produce --topic payments --nb-messages 1 --key test --value "this is not avro" --value-format raw > /dev/null

log "💳 Payments p3 and p4"
produce_payment p3 '{"id":"p3","amount":30.0}'
produce_payment p4 '{"id":"p4","amount":40.0}'

wait_for_records payments-processed '(map(.key) | sort) == ["p1","p2","p3","p4"]' "streams-serde-errors processed p1 to p4"
# each instance gets task 0_2 (partition 2, the bad record) in turn, at each rebalance, and dies on it
log "⏳ the instances of streams-serde-errors-fail-on-poison-pill stop one after the other"
for container in streams streams2 streams3
do
    wait_for_log_since "$started_at" "fail-on-poison-pill state transition from PENDING_ERROR to ERROR" $container > /dev/null
done

log "📒 payments-processed-fail-demo, the output of streams-serde-errors-fail-on-poison-pill:"
consume_json payments-processed-fail-demo | jq -c '{key, offset}'
