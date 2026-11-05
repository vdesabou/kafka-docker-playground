#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/streams-functions.bash

# stream-table join (repartition to be co-partitioned), foreign-key join (subscription topics), and a join of two
# topics that are not co-partitioned, which silently loses join results (copartition-demo application)
start_streams_scenario join

# produces a record with key $2 to topic $1, value $3 (flat JSON)
function produce_json () {
    playground topic produce --topic "$1" --nb-messages 1 --key "$2" --value "$3" --value-format raw > /dev/null
}

log "📇 Tables first: customers c1 and c2 (3 partitions), products p1 and p2"
produce_json customers c1 '{"name":"Alice","tier":"gold"}'
produce_json customers c2 '{"name":"Bob","tier":"silver"}'
produce_json products p1 '{"name":"keyboard","price":50}'
produce_json products p2 '{"name":"mouse","price":20}'

log "🛒 Orders o1 (c1, p1), o2 (c2, p2) and o3 (c3: unknown customer, p1), keyed by order id (6 partitions)"
produce_json orders o1 '{"customer":"c1","product":"p1","quantity":2}'
produce_json orders o2 '{"customer":"c2","product":"p2","quantity":1}'
produce_json orders o3 '{"customer":"c3","product":"p1","quantity":5}'

log "🔗 Stream-table join: the orders are re-keyed by customer and repartitioned (orders-customers-join-repartition), o3 is dropped (inner join, no customer c3)"
wait_for_records orders-enriched '(map(.value.order_id) | sort) == ["o1","o2"]' "o1 and o2 joined with their customer, o3 dropped"

log "🔑 Foreign-key join of the orders table with the products table: all 3 orders, no repartition of the orders by product"
wait_for_records orders-with-product '(map(.key) | unique) == ["o1","o2","o3"]' "o1, o2 and o3 joined with their product"

log "✏️ Product p1 renamed: the foreign-key join re-emits the orders of p1 (o1 and o3), through the subscription topics"
produce_json products p1 '{"name":"mechanical keyboard","price":80}'
wait_for_records orders-with-product '[group_by(.key)[] | max_by(.offset) | select(.key == "o1" or .key == "o3") | .value.product.name] == ["mechanical keyboard","mechanical keyboard"]' "the latest o1 and o3 have the new product name, o2 unchanged"

log "🕰️ Customer c3 created now: a stream-table join is not retroactive, o3 stays dropped, a new order o4 of c3 is joined"
produce_json customers c3 '{"name":"Carol","tier":"bronze"}'
produce_json orders o4 '{"customer":"c3","product":"p2","quantity":3}'
wait_for_records orders-enriched '(map(.value.order_id) | sort) == ["o1","o2","o4"]' "o4 joined with customer c3, o3 still not there"

log "📚 Internal topics of the application: the repartition topic, the changelogs, and the subscription topics of the foreign-key join"
playground topic list 2> /dev/null | grep "streams-join-" || true

log "🚫 copartition-demo: joins orders-by-customer (6 partitions, keyed by customer) with customers (3 partitions) directly, without repartition"
log "📤 Orders of c1, c2 and c3 to orders-by-customer: a key lands in the same partition number in both topics only if murmur2 % 6 == murmur2 % 3"
log "   c2: partition 1 in both. c1 and c3: partition 5 of orders-by-customer, partition 2 of customers (task 0_5 has no partition of customers)"
produce_json orders-by-customer c1 '{"order_id":"x1","product":"p1"}'
produce_json orders-by-customer c2 '{"order_id":"x2","product":"p1"}'
produce_json orders-by-customer c3 '{"order_id":"x3","product":"p1"}'

# the behaviour depends on the version: Kafka Streams 3.0 refuses the topology (TopologyException: Topics not
# co-partitioned), 4.x only validates co-partitioning when there are repartition topics and silently loses join results
MAX_WAIT=120
CUR_WAIT=0
while true
do
    refused=$(for container in streams streams2 streams3; do playground container logs --container $container --no-follow --grep "Topics not co-partitioned" 2> /dev/null; done | head -1)
    if [ -n "$refused" ]
    then
        log "✅ Kafka Streams $KAFKA_CLIENT_TAG refuses the topology, the copartition-demo application stops (ERROR):"
        echo "$refused" | grep -o "TopologyException.*" | cut -c1-250
        break
    fi
    # only consume the output once it exists: consuming a missing topic waits for minutes
    if playground topic list 2> /dev/null | grep -qx "orders-by-customer-enriched" && [ "$(consume_json orders-by-customer-enriched | jq -s -c 'map(.key) | sort')" == '["c2"]' ]
    then
        log "✅ Kafka Streams $KAFKA_CLIENT_TAG does not refuse the topology ('Skipping the repartition topic validation since there are no repartition topics', 6 tasks)"
        log "   orders-by-customer-enriched: only c2 joined, the orders of c1 and c3 are silently lost (no error, no dropped-records-total)"
        playground container logs --container streams --no-follow --grep "Skipping the repartition topic validation" 2> /dev/null | grep "copartition-demo" | cut -c1-250 | head -1 || true
        break
    fi
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ copartition-demo: neither 'Topics not co-partitioned' in the logs nor only c2 in orders-by-customer-enriched after $MAX_WAIT seconds"
        exit 1
    fi
done
