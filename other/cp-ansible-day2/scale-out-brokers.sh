#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/day2-utils.bash

# 1 broker -> 3 brokers on a running cluster deployed by cp-ansible (the broker-scale-up scenario of cp-ansible), with a
# producer and a sink connector running through it. The classic surprise: the new brokers get nothing, the existing
# topics (and the internal ones) keep their replicas until they are reassigned.
day2_require_plaintext
unset ENABLE_KAFKA_NODES

log "Step 1: a cluster with one broker, deployed by cp-ansible"
playground start-environment --environment ansible --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"
day2_start_workload

log "Step 2: two new hosts, broker2 and broker3, in the inventory and deployed by the playbook (the running hosts are not touched)"
playground ansible add-host broker2 broker3
playground ansible playbook --limit broker2,broker3
playground broker health
day2_report_workload "after adding the brokers"

log "Step 3: the new brokers hold nothing: the replicas of the existing topics stay on broker 1"
playground topic describe -t "$DAY2_TOPIC"
playground topic describe -t __consumer_offsets | head -3

log "Step 4: replication factor 3 for the topic, partition by partition, then min.insync.replicas 2"
partition=0
for replicas in 1,2,3 2,3,1 3,1,2
do
    playground topic reassign --topic "$DAY2_TOPIC" --partition $partition --replicas $replicas
    partition=$((partition + 1))
done
playground topic alter --topic "$DAY2_TOPIC" --add-config min.insync.replicas=2
playground topic describe -t "$DAY2_TOPIC"
day2_report_workload "after the reassignment"

log "Step 5: broker 1 stopped: the topic stays writable (3 replicas, min.insync.replicas 2)"
log "   but __consumer_offsets and the internal topics of connect still have one replica, on broker 1: the sink connector stalls until it is back"
since=$(day2_now)
playground broker stop --broker 1
sleep 30
acks_down=$(day2_acks_since "$since")
day2_report_workload "with broker 1 stopped"
log "📤 records acked while broker 1 was down: $acks_down"
playground broker start --broker 1
if [ "$acks_down" -eq 0 ]
then
    logerror "❌ the producer should keep writing with broker 1 down (replication factor 3, min.insync.replicas 2)"
    exit 1
fi

log "Step 6: no record lost"
day2_check_no_loss
