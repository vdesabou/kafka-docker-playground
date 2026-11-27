#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# the Kafka Streams application of other/kafka-streams, scenario join: streams-join-copartition-demo joins the stream
# orders-by-customer (keyed by customer) with the table customers, directly
cd "${DIR}/../../other/kafka-streams"
DIR="$PWD"
source "${DIR}/streams-functions.bash"
start_streams_scenario join

function produce_json () {
    playground topic produce --topic "$1" --nb-messages 1 --key "$2" --value "$3" --value-format raw > /dev/null
}

log "📇 Customers c1, c2 and c3"
produce_json customers c1 '{"name":"Alice","tier":"gold"}'
produce_json customers c2 '{"name":"Bob","tier":"silver"}'
produce_json customers c3 '{"name":"Carol","tier":"bronze"}'

# 💥 orders-by-customer was created by another team, with 6 partitions; customers has 3
log "🛒 Orders x1 (c1), x2 (c2) and x3 (c3), keyed by customer"
produce_json orders-by-customer c1 '{"order_id":"x1","product":"p1"}'
produce_json orders-by-customer c2 '{"order_id":"x2","product":"p1"}'
produce_json orders-by-customer c3 '{"order_id":"x3","product":"p1"}'

wait_for_records orders-by-customer-enriched '(map(.key) | sort) == ["c2"]' "the enrichment wrote its results"
sleep 10
log "📒 orders-by-customer-enriched, the output of streams-join-copartition-demo:"
consume_json orders-by-customer-enriched | jq -c '{key, value}'
