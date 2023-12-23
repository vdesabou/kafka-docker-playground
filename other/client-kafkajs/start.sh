#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure control-center is not disabled
export ENABLE_CONTROL_CENTER=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" -a -b

log "Create a topic kafkajs"
docker exec broker kafka-topics --create --topic kafkajs --partitions 3 --replication-factor 1 --bootstrap-server broker:9092

log "Starting producer"
docker exec -i client-kafkajs node /usr/src/app/producer.js > /dev/null 2>&1 &

log "Starting consumer. Logs are in /tmp/result.log"
docker exec -i client-kafkajs node /usr/src/app/consumer.js > /tmp/result.log 2>&1 &
sleep 15
tail -10 /tmp/result.log
grep "kafkajs" /tmp/result.log