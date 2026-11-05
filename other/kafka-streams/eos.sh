#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/streams-functions.bash

# exactly-once: the count topology with processing.guarantee=exactly_once_v2. An instance paused in the middle of a
# transaction becomes a zombie: its tasks move, it is fenced when it comes back, and the counts stay exact
start_streams_scenario eos

log "📤 Producing 1000 records to eos-input (6 partitions)"
playground topic produce --topic eos-input --nb-messages 1000 --value "record-%g" --value-format raw > /dev/null

log "🔢 read_committed: only the committed transactions of the application are visible"
wait_for_total_count eos-output 1000 read_committed

log "🧾 The transactional producers of the application, one per stream thread (transactional id <application.id>-<process id>-<thread>)"
playground broker transactions list --pattern "streams-eos" || true

log "📤 Producing 3000 more records at 100 records/s, in the background"
playground topic produce --topic eos-input --nb-messages 3000 --throughput 100 --value "record-%g" --value-format raw > /dev/null 2>&1 &
produce_pid=$!
sleep 8

log "⏸️ Pausing streams2 in the middle of its transactions: it becomes a zombie. After consumer.session.timeout.ms (10s) its tasks move to streams and streams3, its open transaction is aborted after producer.transaction.timeout.ms (10s)"
playground container pause --container streams2
playground broker transactions list --pattern "streams-eos" --state Ongoing || true

wait $produce_pid
log "📤 The 3000 records are produced"

log "🔢 Exactly once: the counts add up to 4000 exactly, nothing processed twice although the tasks of streams2 moved in the middle of a transaction"
wait_for_total_count eos-output 4000 read_committed

log "▶️ Resuming streams2: the zombie finds out it was fenced (its tasks belong to another instance now), closes its tasks and rejoins"
resumed_at=$(now)
playground container resume --container streams2
wait_for_log_since "$resumed_at" "fenced\|Fenced\|TaskMigrated\|missed a rebalance" streams2
wait_for_log_since "$resumed_at" "Application state transition from REBALANCING to RUNNING" streams2 > /dev/null

log "📤 Producing 1000 more records with the 3 instances back"
playground topic produce --topic eos-input --nb-messages 1000 --value "record-%g" --value-format raw > /dev/null
wait_for_total_count eos-output 5000 read_committed

# records, not counts: the latest count of each bucket is the same, but the aborted transactions left records behind
uncommitted=$(playground topic consume --topic eos-output --count 2> /dev/null)
committed=$(playground topic consume --topic eos-output --count --isolation-level read_committed 2> /dev/null)
log "🔍 eos-output holds $uncommitted records for read_uncommitted consumers, $committed for read_committed ones: the $(( uncommitted - committed )) others belong to aborted transactions (the zombie's), never visible to read_committed consumers"
