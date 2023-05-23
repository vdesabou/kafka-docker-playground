#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "6.9.9"; then
    logwarn "WARN: Cluster Linking is GA since CP 7.0 only"
    exit 111
fi

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Create topic demo"
docker exec broker-europe kafka-topics --create --topic demo --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1

log "Sending 20 messages in US cluster"
seq -f "us_sale_%g ${RANDOM}" 20 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo"

log "Verify we have received the data in source cluster using consumer group id my-consumer-group, we read only 5 messages"
playground topic consume --topic demo --min-expected-messages 5

log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 seconds + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000 + consumer.offset.sync.json set to all consumer groups + auto.create.mirror.topics.enable=true + automatic-topic-creation-filters.json  set to all the topics prefixed by 'demo' )"
docker cp consumer.offset.sync.json broker-europe:/tmp/consumer.offset.sync.json
docker cp automatic-topic-creation-filters.json broker-europe:/tmp/automatic-topic-creation-filters.json
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link demo-link --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000,auto.create.mirror.topics.enable=true --consumer-group-filters-json-file /tmp/consumer.offset.sync.json --topic-filters-json-file /tmp/automatic-topic-creation-filters.json

log "Wait for the demo topic to be automatically created"
sleep 10

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092

log "Wait 6 seconds for consumer.offset sync to happen (2 times consumer.offset.sync.ms=3000)"
sleep 6

log "Verify that current offset is consistent in source and destination"
log "Describe consumer group my-consumer-group at Source cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group my-consumer-group

log "Describe consumer group my-consumer-group at Destination cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group

log "Consume from the mirror topic on the destination cluster and verify consumer offset is working, it should start at 6"
playground topic consume --topic demo --min-expected-messages 5

log "Describe consumer group my-consumer-group at Destination cluster."
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group
log "sleep 6 seconds"
sleep 6
log "Describe consumer group my-consumer-group at Destination cluster. Note: the current-offset has been overwritten due to the consumer offset sync"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group

log "Stop consumer offset sync for consumer group my-consumer-group"
echo "consumer.offset.group.filters={\"groupFilters\": [ \
  { \
    \"name\": \"*\", \
    \"patternType\": \"LITERAL\", \
    \"filterType\": \"INCLUDE\" \
  }, \
  { \
    \"name\": \"my-consumer-group\", \
    \"patternType\": \"LITERAL\", \
    \"filterType\": \"EXCLUDE\" \
  } \
]}" > newFilters.properties
docker cp newFilters.properties broker-europe:/tmp/newFilters.properties
docker exec broker-europe kafka-configs --bootstrap-server broker-europe:9092 --alter --cluster-link demo-link --add-config-file /tmp/newFilters.properties

sleep 6

log "Consume from the source cluster another 10 messages, up to 15"
playground topic consume --topic demo --min-expected-messages 10

log "Consume from the destination cluster, it will continue from it's last offset 10"
playground topic consume --topic demo --min-expected-messages 5

log "Verify that the topic mirror is read-only"
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic demo"

log "Modify the source topic config, set retention.ms"
docker container exec -i connect-us kafka-configs --alter --topic demo --add-config retention.ms=123456890 --bootstrap-server broker-us:9092

log "Check the Source Topic Configuration"
docker container exec -i connect-us kafka-configs --describe --topic demo --bootstrap-server broker-us:9092

log "Wait 6 seconds (default is 5 minutes metadata.max.age.ms, but we modified it to 5 seconds)"
sleep 6

log "Check the Destination Topic Configuration"
docker container exec -i connect-us kafka-configs --describe --topic demo --bootstrap-server broker-europe:9092

log "Alter the number of partitions on the source topic"
docker container exec -i connect-us kafka-topics --alter --topic demo --partitions 8 --bootstrap-server broker-us:9092

log "Verify the change on the source topic"
docker container exec -i connect-us kafka-topics --describe --topic demo --bootstrap-server broker-us:9092

log "Wait 6 seconds (default is 5 minutes metadata.max.age.ms, but we modified it to 5 seconds)"
sleep 6

log "Verify the change on the destination topic"
docker container exec -i connect-us kafka-topics --describe --topic demo --bootstrap-server broker-europe:9092

log "List mirror topics"
docker container exec -i connect-us kafka-cluster-links --list --link demo-link --include-topics --bootstrap-server broker-europe:9092

log "Cut over the mirror topic to make it writable"
docker container exec -i connect-us kafka-mirrors --promote --topics demo --bootstrap-server broker-europe:9092

log "Produce to both topics to verify divergence"

log "Sending data again in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo"

log "Sending data in EUROPE cluster"
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic demo"

log "Delete the cluster link"
docker container exec -i connect-us kafka-cluster-links --bootstrap-server broker-europe:9092 --delete --link demo-link