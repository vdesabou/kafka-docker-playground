#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "7.9.99"
then
    logwarn "this exercise is about KRaft controllers: run it with CP 8 or later"
    exit 111
fi

# brokers 1, 2 and 3, controllers 4, 5 and 6 (same as playground run --enable-multiple-brokers --enable-multiple-controllers)
export ENABLE_KAFKA_NODES=true
export ENABLE_CONTROLLER_NODES=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

playground topic create --topic payments --nb-partitions 3 --replication-factor 3

log "💥 the night before: two of the three controllers went down (a maintenance that did not finish)"
playground container kill -c controller2 -c controller3

log "Sending 5 payments"
playground container exec -c broker --command 'for i in $(seq 1 5); do echo "payment-$i"; done | kafka-console-producer --bootstrap-server broker:9092,broker2:9092,broker3:9092 --topic payments 2>&1 | grep -E "ERROR|Exception"' || true
playground topic get-offsets --topic payments || true

log "The application team asks for a new topic"
set +e
playground topic create --topic refunds --nb-partitions 3 --replication-factor 3
set -e
