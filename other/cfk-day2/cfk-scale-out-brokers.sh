#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/cfk-day2-utils.bash

# 1 → 3 brokers on a running cluster deployed by Confluent for Kubernetes (spec.replicas), with a producer and a sink
# connector running through it, then a broker removed:
#   1. scale out: CFK creates the new brokers, then rolls every broker once
#   2. the new brokers hold nothing: Self-Balancing is enabled by CFK (EMPTY_BROKER trigger), but nothing moved
#   3. the topic reassigned to replication factor 3 (playground topic reassign): it survives a broker restart
#   4. the classic mistake, spec.replicas 3 → 2: the CR says RUNNING, nothing happens, the operator's shrink is refused
#      (a topic with 3 replicas can't fit on 2 brokers)
day2_require_cfk
export DAY2_SINGLE_BROKER=1

function day2_topic_layout () {
    # partition, leader, replicas, isr of a topic ($1)
    log_command kubectl -n confluent exec connect-0 -c connect -- kafka-topics --bootstrap-server kafka:9071 --describe --topic "$1"
    kubectl -n confluent exec connect-0 -c connect -- kafka-topics --bootstrap-server kafka:9071 --describe --topic "$1" 2> /dev/null | grep "Partition:" | awk '{ printf "   %s partition %s  leader %s  replicas %-6s isr %s\n", $2, $4, $6, $8, $10 }'
}

function day2_balancer_status () {
    log_command kubectl -n confluent exec kafka-0 -c kafka -- kafka-rebalance-cluster --bootstrap-server kafka:9071 --status
    kubectl -n confluent exec kafka-0 -c kafka -- kafka-rebalance-cluster --bootstrap-server kafka:9071 --status 2> /dev/null | grep -E "Balancer status|running on" | sed 's/^/   /' || true
}

log "Step 1: Confluent Platform $TAG deployed by CFK, 3 KRaft controllers, 1 broker"
day2_start_cfk
kubectl -n confluent get pods -l app=kafka | sed 's/^/   /'

log "Step 2: a workload, on a topic with one replica (one broker)"
day2_start_workload
day2_topic_layout "$DAY2_TOPIC"

log "Step 3: 3 brokers (spec.replicas: 3)"
errors_before=$(day2_send_errors)
since=$(day2_now)
playground cfk patch kafka/kafka '{"spec": {"replicas": 3}}'
errors_scale=$(( $(day2_send_errors) - errors_before ))
pause_scale=$(day2_longest_pause "$since")
day2_pod_stops "$since"
day2_report_workload "after the scale out"
log "🔁 the scale out: $errors_scale send errors, longest time without an ack ${pause_scale}s (CFK rolled every broker once, the new ones included: their configuration depends on the size of the cluster)"

log "Step 4: the new brokers hold nothing"
sleep 60
day2_topic_layout "$DAY2_TOPIC"
day2_topic_layout __consumer_offsets | head -3
log_command kubectl -n confluent exec kafka-0 -c kafka -- grep -E '^confluent.balancer' /opt/confluentinc/etc/kafka/kafka.properties
kubectl -n confluent exec kafka-0 -c kafka -- sh -c "grep -E '^confluent.balancer.enable' /opt/confluentinc/etc/kafka/kafka.properties" | sed 's/^/   /'
day2_balancer_status
moved=$(kubectl -n confluent exec connect-0 -c connect -- kafka-topics --bootstrap-server kafka:9071 --describe --topic "$DAY2_TOPIC" 2> /dev/null | grep "Partition:" | awk '{print $8}' | grep -cvE '^0$' || true)
if [ "$moved" -eq 0 ]
then
    log "💥 Self-Balancing is enabled by CFK (trigger EMPTY_BROKER), and nothing moved: 0 partition of $DAY2_TOPIC on the new brokers. Every topic keeps its single replica on kafka-0 (the internal topics too)"
else
    log "⚖️ Self-Balancing moved $moved partition(s) of $DAY2_TOPIC to the new brokers (still one replica each)"
fi

log "Step 5: the topic reassigned to 3 replicas, spread over the 3 brokers (playground topic reassign)"
replicas=("0,1,2" "1,2,0" "2,0,1")
for partition in 0 1 2
do
    playground topic reassign --topic "$DAY2_TOPIC" --partition $partition --replicas "${replicas[$partition]}"
done
day2_topic_layout "$DAY2_TOPIC"

log "Step 6: kafka-0 restarted: the topic stays writable"
acks_before=$(day2_count producer_send_success)
run_logged kubectl -n confluent delete pod kafka-0
sleep 60
log_command kubectl -n confluent wait --for=condition=Ready pod/kafka-0 --timeout=600s
kubectl -n confluent wait --for=condition=Ready pod/kafka-0 --timeout=600s > /dev/null
acks_restart=$(( $(day2_count producer_send_success) - acks_before ))
log "📤 records acked in the minute kafka-0 restarted: $acks_restart"

log "Step 7: the classic mistake, a broker removed with spec.replicas 3 → 2"
set +e
out=$(mktemp)
playground cfk patch kafka/kafka '{"spec": {"replicas": 2}}' --timeout 300 2>&1 | tee "$out"
shrink_rc=${PIPESTATUS[0]}
set -e
shrink_refused=$(grep -c "Can't remove brokers" "$out" || true)
rm -f "$out"
log_command kubectl -n confluent get statefulset kafka -o 'jsonpath={.spec.replicas}'
log "💥 the CR says $(kubectl -n confluent get kafka kafka -o jsonpath='{.status.phase}') and still runs $(kubectl -n confluent get statefulset kafka -o jsonpath='{.spec.replicas}') brokers: CFK asks the brokers to remove broker 2 first (it moves its replicas away), and they refuse, a topic with 3 replicas can't fit on 2 brokers"
log "   back to 3 (spec.replicas: 3): drain a broker only when the others can hold its replicas"
playground cfk patch kafka/kafka '{"spec": {"replicas": 3}}' --timeout 300 || true

log "Step 8: no record lost"
day2_check_no_loss
log "📋 scale out: $errors_scale send errors (longest pause ${pause_scale}s); partitions moved by Self-Balancing: $moved; acks while kafka-0 restarted (3 replicas): $acks_restart; scale down refused: $shrink_refused"
if [ "$shrink_rc" -eq 0 ] || [ "$shrink_refused" -eq 0 ] || [ "$acks_restart" -eq 0 ]
then
    logerror "❌ expected the scale down to be refused (Can't remove brokers) and the topic to stay writable while kafka-0 restarted"
    exit 1
fi
