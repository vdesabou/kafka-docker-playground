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

# number of records of topic $1 that a consumer reads, with isolation level $2 (read_committed stops at the last stable offset)
function nb_records () {
    playground topic consume --topic "$1" --isolation-level "${2:-read_uncommitted}" --count 2>/dev/null | tail -1
}

log "Step 1: what the cluster looks like, and its health"
playground broker describe
playground broker health --wait-healthy --max-wait 120

playground topic create --topic orders --nb-partitions 3 --replication-factor 3 --config min.insync.replicas=2
playground topic produce -t orders --nb-messages 100 --value "order-%g"

log "Step 2: the key metrics of each broker, for topic orders"
playground broker metrics --topic orders

log "Step 3: broker 3 crashes"
playground broker stop --broker 3 --kill
set +e
playground broker health
rc=$?
set -e
if [ $rc -ne 1 ]
then
    logerror "❌ broker health should exit with 1 when a broker is down"
    exit 1
fi
if [ "$(playground broker health --json | jq -r '.brokers.not_registered | map(.id) | join(",")')" != "3" ]
then
    logerror "❌ broker 3 should be reported as down"
    exit 1
fi

log "Step 4: acks=all producers still work, 2 replicas are in sync (min.insync.replicas=2)"
playground topic produce -t orders --nb-messages 100 --value "order-while-broker-3-is-down-%g"

log "Step 5: broker 3 starts again, and catches up"
playground broker start --broker 3

log "Step 6: rolling restart of the 3 brokers, one at a time"
playground broker rolling-restart
if [ "$(nb_records orders)" != "200" ]
then
    logerror "❌ topic orders should still have 200 records"
    exit 1
fi

log "Step 7: a transactional producer stops with its transaction open"
playground topic create --topic payments --nb-partitions 1 --replication-factor 3
# the coordinator aborts it after --transaction-timeout (15 minutes, the maximum by default)
playground topic produce -t payments --nb-messages 10 --value "payment-in-transaction-%g" --transactional-id payments-txn --transaction open --transaction-timeout 900000

playground broker transactions list --state Ongoing
playground broker transactions describe --transactional-id payments-txn
playground broker transactions describe-producers --topic payments
start_offset=$(playground broker transactions describe-producers --topic payments 2>/dev/null | awk '$1 == "0" && $NF == "⚠️" {print $(NF-1)}')
if [ -z "$start_offset" ]
then
    logerror "❌ describe-producers should show the open transaction of partition 0"
    exit 1
fi

log "Step 8: records produced after it are invisible to read_committed consumers: the open transaction holds the last stable offset"
playground topic produce -t payments --nb-messages 5 --value "payment-%g"
uncommitted=$(nb_records payments)
committed=$(nb_records payments read_committed)
log "read_uncommitted: $uncommitted records, read_committed: $committed records"
if [ "$committed" != "0" ]
then
    logerror "❌ read_committed consumers should see 0 records while the transaction is open"
    exit 1
fi

log "Step 9: not hanging (its coordinator still tracks it, it would be aborted after transaction.timeout.ms), abort it anyway"
playground broker transactions find-hanging --topic payments
playground broker transactions abort --topic payments --partition 0 --start-offset "$start_offset"
committed=$(nb_records payments read_committed)
log "read_committed: $committed records (the aborted records are skipped)"
if [ "$committed" != "5" ]
then
    logerror "❌ read_committed consumers should see the 5 records produced after the transaction once it is aborted"
    exit 1
fi

log "Step 10: the 5 records produced after the transaction, read with read_committed"
playground topic consume --topic payments --isolation-level read_committed --min-expected-messages 5 --timeout 60
