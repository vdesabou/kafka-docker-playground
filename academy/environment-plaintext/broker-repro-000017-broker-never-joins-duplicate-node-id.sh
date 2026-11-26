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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000017-broker-never-joins-duplicate-node-id.yml"
set -e

log "Adding broker3 to the cluster"
playground container logs -c broker3 --wait-for-log "DUPLICATE_BROKER_REGISTRATION" --max-wait 180 > /dev/null || true

# the cluster is not healthy: that is the exercise (exit 0 for the run)
playground broker health || true
