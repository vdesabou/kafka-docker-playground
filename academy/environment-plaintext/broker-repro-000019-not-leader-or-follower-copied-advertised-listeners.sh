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
set +e
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000019-not-leader-or-follower-copied-advertised-listeners.yml"
set -e

log "Creating topic orders: 6 partitions, 3 replicas"
playground topic create --topic orders --nb-partitions 6 --replication-factor 3 || true

# the console producer of the broker image (playground topic produce waits for Schema Registry, which can be stuck too)
log "Sending 12 orders, one per customer"
playground container exec -c broker --command 'for i in $(seq 1 12); do echo "customer$i:order-$i"; done | kafka-console-producer --bootstrap-server broker:9092 --topic orders --reader-property parse.key=true --reader-property key.separator=: --command-property delivery.timeout.ms=20000 --command-property request.timeout.ms=10000 2>&1 | grep -E "ERROR|Exception"' || true

log "What landed in each partition, and who leads it"
playground topic get-offsets --topic orders || true
playground topic describe --topic orders || true
