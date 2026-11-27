#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

playground topic create --topic orders --nb-partitions 3

log "💥 months ago, for a load test that is long over"
playground quota set --client-id orders-service --producer-byte-rate 51200 > /dev/null

log "The orders service sends 3000 orders of 1 KB: it usually takes a couple of seconds"
playground topic produce --topic orders --nb-messages 3000 --record-size 1000 --forced-value '{"order": %g}' --producer-property client.id=orders-service
