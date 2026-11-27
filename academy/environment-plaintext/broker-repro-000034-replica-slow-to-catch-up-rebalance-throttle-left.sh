#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# brokers 1, 2 and 3 (same as playground run --enable-multiple-brokers)
export ENABLE_KAFKA_NODES=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Last week: the cluster grew from 2 to 3 brokers, topic orders was still on brokers 1 and 2"
playground topic create --topic orders --nb-partitions 6 --replication-factor 2
playground topic reassign --topic orders --replicas 1,2
playground topic produce --topic orders --nb-messages 2000 --record-size 1000 --forced-value '{"order": %g, "week": "last"}'

# the rebalancer reads the sizes of the partitions from the metrics topic (_confluent-metrics): wait for a report
log "Waiting 60 seconds for the Confluent Metrics Reporter to publish the sizes of the partitions"
sleep 60

log "The ops team ran Auto Data Balancer, with a replication throttle of 100 KB/s to protect the clients"
playground container exec -c broker --command "confluent-rebalancer execute --bootstrap-server broker:9092 --metrics-bootstrap-server broker:9092 --topics orders --throttle 100000 --force"

# 💥 nobody ran confluent-rebalancer status or finish after it: the moves complete, the throttle stays
log "⏳ the moves complete during the night"
MAX_WAIT=300
CUR_WAIT=0
until playground --output-level ERROR topic describe --topic orders 2>&1 | grep "Partition:" | grep -q -E "Replicas: ([0-9],)*3" && ! playground --output-level ERROR topic describe --topic orders 2>&1 | grep -q -E "Adding Replicas|Removing Replicas"
do
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ the moves of the rebalance did not complete within $MAX_WAIT seconds"
        exit 1
    fi
done

log "Today: broker 3 is stopped for an OS patch, the orders keep coming (40 MB)"
playground broker stop --broker 3
playground topic produce --topic orders --nb-messages 40000 --record-size 1000 --forced-value '{"order": %g, "week": "this"}'

log "Broker 3 is back"
playground broker start --broker 3 --no-wait
sleep 60

playground broker health || true
