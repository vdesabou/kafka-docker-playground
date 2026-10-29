#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-broker
lab_require_plaintext
# brokers 1, 2 and 3 (same as playground run --enable-multiple-brokers)
export ENABLE_KAFKA_NODES=true
lab_start_environment

log "Step 1: the shape and the health of the cluster"
lab_run playground broker describe
lab_expect_exit 0
lab_expect_contains "ID  ENDPOINT      RACK  FENCED  CONTAINER"
lab_expect_contains "3   broker3:9092  null  false   broker3"
lab_expect_contains "Observers (brokers):   1,2,3"
lab_run playground broker health
lab_expect_exit 0
lab_expect_contains "✅ all brokers are registered: 1,2,3"
lab_expect_not_contains "⚠️ topics with a replication factor below min.insync.replicas" "no warning on a fresh environment"
lab_expect_contains "✅ cluster is healthy"
lab_run playground topic describe --topic connect-offsets
lab_expect_contains "ReplicationFactor: 3" "internal topics have 3 replicas with 3 brokers"

log "Step 2: a broker crashes"
lab_run playground topic create --topic lab-orders --nb-partitions 3 --replication-factor 3 --config min.insync.replicas=2
lab_expect_exit 0
lab_run playground broker stop --broker 3 --kill
lab_expect_exit 0
lab_expect_contains "🔫 Killing broker 3 (container broker3): no controlled shutdown, like a crash"
lab_run playground broker health
lab_expect_exit 1
lab_expect_contains "❌ broker 3 (container broker3)"
lab_expect_contains "✅ no unavailable (no leader) partition"
lab_expect_contains "❌ cluster is not healthy: brokers down: 3"
lab_run playground topic produce -t lab-orders --nb-messages 10 --value 'order-%g' --producer-property acks=all
lab_expect_exit 0
lab_expect_contains "📤 produced 10 records to topic lab-orders"

log "Step 3: it comes back, then a rolling restart"
lab_run playground broker start --broker 3
lab_expect_exit 0
lab_expect_contains "✅ broker 3 is registered, waiting for its replicas to be back in sync"
lab_expect_contains "✅ cluster is healthy, broker 3 started in"
lab_run playground broker stop --broker 3 --kill
lab_run playground broker rolling-restart
lab_expect_exit 1
lab_expect_contains "❌ cluster is not healthy before the rolling restart: brokers down: 3"
lab_run playground broker start --broker 3
lab_expect_exit 0
lab_run playground broker rolling-restart
lab_expect_exit 0
lab_expect_contains "🔄 [1/3] Restarting broker 1 (container broker)"
lab_expect_contains "🎉 rolling restart of brokers 1,2,3 done in"

log "Step 4: an open transaction blocks read_committed consumers"
lab_run playground topic produce -t lab-payments --nb-messages 10 --value 'in-transaction-%g' --transactional-id lab-payments-txn --transaction open --transaction-timeout 900000
lab_expect_exit 0
lab_expect_contains "transaction left open, the coordinator aborts it after transaction.timeout.ms (900000 ms)"
lab_run playground topic produce -t lab-payments --nb-messages 5 --value 'after-%g'
lab_expect_exit 0
lab_run playground topic consume --topic lab-payments --count
lab_expect_equals "$(echo "$LAB_OUTPUT" | tail -1)" "15" "read_uncommitted records"
lab_run playground topic consume --topic lab-payments --isolation-level read_committed --count
lab_expect_equals "$(echo "$LAB_OUTPUT" | tail -1)" "0" "read_committed records while the transaction is open"
lab_run playground broker transactions list --state Ongoing
lab_expect_exit 0
lab_expect_contains "lab-payments-txn"
lab_run playground broker transactions describe-producers --topic lab-payments
lab_expect_exit 0
lab_expect_contains "OPEN_TRANSACTION_START_OFFSET"
lab_expect_contains "0 ⚠️"

log "Step 5: not hanging, aborted anyway"
lab_run playground broker transactions find-hanging --topic lab-payments
lab_expect_exit 0
lab_expect_contains "✅ no hanging transaction"
lab_run playground broker transactions abort --topic lab-payments --partition 0 --start-offset 0
lab_expect_exit 0
lab_expect_contains "✅ transaction aborted"
lab_run playground topic consume --topic lab-payments --isolation-level read_committed --count
lab_expect_equals "$(echo "$LAB_OUTPUT" | tail -1)" "5" "read_committed records once the transaction is aborted"

log "Step 6: metrics and API versions"
lab_run playground broker metrics --topic lab-orders
lab_expect_exit 0
lab_expect_contains "METRIC BROKER 1 BROKER 2 BROKER 3"
lab_expect_equals "$(awk '$1 == "Under-replicated" {print $3}' <<< "$LAB_OUTPUT")" "0" "under-replicated partitions of broker 1"
lab_run playground broker describe --api-versions --broker 2
lab_expect_exit 0
lab_expect_contains "🔌 API versions supported by broker 2"
lab_expect_contains "Produce(0):"

log "✅ all the outputs of the page are as expected"
