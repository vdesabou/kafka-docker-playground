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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000018-broker-rejected-inconsistent-cluster-id.yml"
set -e

# the cluster is not healthy: that is the exercise (exit 0 for the run)
playground broker health || true
