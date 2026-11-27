#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "7.9.99"
then
    logwarn "this exercise is about KRaft brokers: run it with CP 8 or later"
    exit 111
fi

# brokers 1, 2 and 3 (same as playground run --enable-multiple-brokers)
export ENABLE_KAFKA_NODES=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "The payments topic, as the application team created it"
playground topic create --topic payments --nb-partitions 3 --replication-factor 2 --config min.insync.replicas=2

log "💥 broker 3 crashes during the night"
playground broker stop --broker 3 --kill

log "The payment service sends 9 payments, with acks=all"
set +e
playground topic produce --topic payments --nb-messages 9 --key "account-%g" --forced-value '{"payment": %g}' --producer-property acks=all --producer-property delivery.timeout.ms=30000 --producer-property request.timeout.ms=10000
set -e

playground topic get-offsets --topic payments || true
