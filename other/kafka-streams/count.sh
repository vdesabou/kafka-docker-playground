#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/streams-functions.bash

# rebalance and restore: the count topology (groupBy → repartition topic, count → state store and changelog)
start_streams_scenario count

log "📤 Producing 1000 records to streams-input (6 partitions)"
playground topic produce --topic streams-input --nb-messages 1000 --value "record-%g" --value-format raw

log "🔢 The application counts them per bucket: groupBy (repartition topic) then count (changelog topic)"
wait_for_total_count streams-output 1000

log "👥 Members of the consumer group and their partitions"
playground consumer-group describe --group streams-count --members

log "🔫 Killing instance streams2: its tasks move to streams and streams3, which restore their state from the changelog topic"
killed_at=$(now)
playground container kill --container streams2

log "📤 Producing 1000 more records while streams2 is down"
playground topic produce --topic streams-input --nb-messages 1000 --value "record-%g" --value-format raw

wait_for_total_count streams-output 2000

log "♻️ Restoration of the tasks of streams2 on the remaining instances"
wait_for_log_since "$killed_at" "Restore completed" streams streams3

log "🔁 Restarting streams2: it first gets standby (warm-up) tasks, then its active tasks back after a follow-up rebalance, and restores their state"
restarted_at=$(now)
playground container restart --container streams2
wait_for_log_since "$restarted_at" "Restore completed" streams2

log "📤 Producing 1000 more records with the 3 instances back"
playground topic produce --topic streams-input --nb-messages 1000 --value "record-%g" --value-format raw

wait_for_total_count streams-output 3000
