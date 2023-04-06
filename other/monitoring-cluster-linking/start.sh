#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "6.9.9"; then
    logwarn "WARN: Cluster Linking is GA since CP 7.0 only"
    exit 111
fi

export DISABLE_CONTROL_CENTER="true"
${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Create topic demo"
docker exec broker-us kafka-topics --create --topic demo --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1

log "Sending 20 messages in US cluster"
seq -f "us_sale_%g ${RANDOM}" 20 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo"

log "Verify we have received the data in source cluster using consumer group id my-replicated-consumer-group, we read only 5 messages"
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --topic demo --from-beginning --max-messages 5 --consumer-property group.id=my-replicated-consumer-group"

log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 seconds + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000 + consumer.offset.sync.json set to all consumer groups)"
docker cp consumer.offset.sync.json broker-europe:/tmp/consumer.offset.sync.json
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link link-us-to-europe --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/consumer.offset.sync.json

log "Initialize the topic mirror for topic demo"
docker exec broker-europe kafka-mirrors --create --mirror-topic demo --link link-us-to-europe --bootstrap-server broker-europe:9092

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092

log "Wait 6 seconds for consumer.offset sync to happen (2 times consumer.offset.sync.ms=3000)"
sleep 6

log "Verify that current offset is consistent in source and destination"
log "Describe consumer group my-consumer-group at Source cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group my-replicated-consumer-group