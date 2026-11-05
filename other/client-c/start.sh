#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -n "$CLIENT_VERSION" ]
then
     log "📦 CLIENT_VERSION is set: building the client-c image with client version $CLIENT_VERSION"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-c container and what it depends on (broker): no connect, nothing to wait for
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service client-c

NB_MESSAGES=10

log "Creating topic c-string"
playground topic create --topic c-string --nb-partitions 3

log "Producing $NB_MESSAGES string records with the C producer (librdkafka)"
playground container exec -c client-c --command "client produce c-string /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the C consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-c --command "client consume c-string /tmp/client.properties $NB_MESSAGES"

log "Checking the consumer group of the C consumer committed the offsets"
playground consumer-group describe --group c-string-group
