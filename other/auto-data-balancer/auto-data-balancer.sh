#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Auto Data Balancer (confluent-rebalancer): a cluster that grew from 2 to 3 brokers, the topic still on the first two.
# It needs the Confluent Metrics Reporter on the brokers (the playground enables it with cp-server) and Self-Balancing
# off (the default of the environment)

# brokers 1, 2 and 3 (same as playground run --enable-multiple-brokers)
export ENABLE_KAFKA_NODES=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Topic orders: 6 partitions, 2 replicas, all of them on brokers 1 and 2 (broker 3 was added later)"
playground topic create --topic orders --nb-partitions 6 --replication-factor 2
playground topic reassign --topic orders --replicas 1,2

log "Sending 30000 records of 1 KB"
playground topic produce --topic orders --nb-messages 30000 --record-size 1000 --forced-value '{"order": %g}'

playground topic describe --topic orders

# the rebalancer reads the sizes of the partitions from the metrics topic (_confluent-metrics): wait for a report
log "Waiting 60 seconds for the Confluent Metrics Reporter to publish the sizes of the partitions"
sleep 60

log "🚀 confluent-rebalancer execute: the plan, then the moves, with a replication throttle of 1 MB/s"
playground container exec -c broker --command "confluent-rebalancer execute --bootstrap-server broker:9092 --metrics-bootstrap-server broker:9092 --topics orders --throttle 1000000 --force --verbose"

log "⏳ confluent-rebalancer status until the moves are done"
MAX_WAIT=300
CUR_WAIT=0
until playground --output-level ERROR container exec -c broker --command "confluent-rebalancer status --bootstrap-server broker:9092" 2>&1 | tee /tmp/adb-status.log | grep -q "No rebalance is currently in progress"
do
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        cat /tmp/adb-status.log
        logerror "❌ the rebalance did not complete within $MAX_WAIT seconds"
        exit 1
    fi
done
cat /tmp/adb-status.log

log "🧹 confluent-rebalancer finish: removes the replication throttle"
playground container exec -c broker --command "confluent-rebalancer finish --bootstrap-server broker:9092"

# the rebalancer changes the preferred leader (the first replica) of some partitions, the leaders themselves move at
# the next preferred leader election (auto.leader.rebalance.enable, every leader.imbalance.check.interval.seconds, 300 s)
log "👑 moving the leaders to their new preferred replicas now"
playground topic elect-leader --topic orders

playground topic describe --topic orders
log "Checking that broker 3 now has replicas of orders"
if ! playground --output-level ERROR topic describe --topic orders 2>&1 | grep "Partition:" | grep -q -E "Replicas: ([0-9],)*3"
then
    logerror "❌ broker 3 has no replica of orders after the rebalance"
    exit 1
fi
if ! playground --output-level ERROR topic describe --topic orders 2>&1 | grep "Partition:" | grep -q "Leader: 3"
then
    logerror "❌ broker 3 leads no partition of orders after the leader election"
    exit 1
fi
log "✅ broker 3 has replicas of orders, and leads some of them"
