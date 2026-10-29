#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
if [ "$PLAYGROUND_ENVIRONMENT" != "plaintext" ]
then
    logwarn "this example needs the 3 brokers of the plaintext environment"
    exit 111
fi

# brokers 1, 2 and 3 (same as playground run --enable-multiple-brokers)
export ENABLE_KAFKA_NODES=true
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

# "<partition> <leader> <replicas>" of each partition of topic orders
function partitions () {
    playground topic describe --topic orders 2>/dev/null | awk '/Partition:/ {for (n = 1; n <= NF; n++) {if ($n == "Partition:") p = $(n+1); if ($n == "Leader:") l = $(n+1); if ($n == "Replicas:") r = $(n+1)} print p, l, r}'
}

playground topic create --topic orders --nb-partitions 3 --replication-factor 2

log "Sending 1000 records of 10 KB (10 MB) to topic orders"
playground topic produce -t orders --nb-messages 1000 --record-size 10000 --value "order-%g"

log "Step 1: move every partition to brokers 2 and 3, with a 1 MB/s replication throttle"
playground topic reassign --topic orders --replicas 2,3 --throttle 1000000
if [ "$(partitions | awk '$3 == "2,3"' | wc -l | tr -d ' ')" != "3" ]
then
    logerror "❌ the replicas of the partitions are not 2,3"
    partitions
    exit 1
fi

log "Step 2: spread the partitions over the 3 brokers again, like a rebalance"
playground topic reassign --topic orders --brokers 1,2,3

log "Step 3: preferred leader election, each partition is led by its first replica"
playground topic elect-leader --topic orders
not_preferred=$(partitions | awk '{split($3, r, ","); if ($2 != r[1]) print $1}')
if [ -n "$not_preferred" ]
then
    logerror "❌ partition(s) $not_preferred are not led by their preferred replica"
    exit 1
fi

# the other replica of partition 0 becomes its leader
read -r p0 p0_leader p0_replicas <<< "$(partitions | awk '$1 == 0')"
new_leader=$(echo "$p0_replicas" | tr ',' '\n' | grep -vx "$p0_leader" | head -1)
log "Step 4: controlled leader move of partition 0 from broker $p0_leader to broker $new_leader"
playground topic elect-leader --topic orders --partition 0 --leader "$new_leader"
if [ "$(partitions | awk '$1 == 0 {print $2}')" != "$new_leader" ]
then
    logerror "❌ broker $new_leader is not the leader of partition 0"
    exit 1
fi

log "Step 5: the records are all still there"
playground topic consume --topic orders --min-expected-messages 1000 --timeout 120 --max-messages 3
