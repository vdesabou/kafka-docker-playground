#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Create topic demo"
docker exec broker-europe kafka-topics --create --topic demo --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 20 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo"

log "Verify we have received the data in source cluster using consumer group id my-consumer-group, we read only 5 messages"
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --topic demo --from-beginning --max-messages 5 --consumer-property group.id=my-consumer-group"

log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 minutes + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000)"
docker cp consumer.offset.sync.all.json broker-europe:/tmp/consumer.offset.sync.all.json
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link-name demo-link --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/consumer.offset.sync.all.json

log "Initialize the topic mirror"
docker exec broker-europe kafka-topics --create --topic demo --mirror-topic demo --link-name demo-link --bootstrap-server broker-europe:9092

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092

log "Wait 6 seconds for consumer.offset sync to happen (2 times consumer.offset.sync.ms=3000)"
sleep 6

log "Verify that current offset is consistent in source and destination"
log "Describe consumer group my-consumer-group at Source cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group my-consumer-group
# GROUP             TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
# my-consumer-group demo            0          5               20              15              -               -               -
log "Describe consumer group my-consumer-group at Destination cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group
# GROUP             TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
# my-consumer-group demo            0          5               20              15              -               -               -
log "Consume from the mirror topic on the destination cluster and verify consumer offset is working, it should start at 6"
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic demo --max-messages 5 --consumer-property group.id=my-consumer-group"
# us_sale_6 7999
# us_sale_7 7999
# us_sale_8 7999
# us_sale_9 7999
# us_sale_10 7999
# Processed a total of 5 messages
log "Describe consumer group my-consumer-group at Destination cluster. FIXTHIS: current-offset has not been updated"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group
# GROUP             TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
# my-consumer-group demo            0          5               20              15              -               -               -

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
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --topic demo --max-messages 10 --consumer-property group.id=my-consumer-group"
# us_sale_6 7999
# us_sale_7 7999
# us_sale_8 7999
# us_sale_9 7999
# us_sale_10 7999
# us_sale_11 7999
# us_sale_12 7999
# us_sale_13 7999
# us_sale_14 7999
# us_sale_15 7999
# Processed a total of 10 messages
log "Consume from the destination cluster, it will continue from it's last offset 6"
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic demo --max-messages 5 --consumer-property group.id=my-consumer-group"
# us_sale_6 7999
# us_sale_7 7999
# us_sale_8 7999
# us_sale_9 7999
# us_sale_10 7999
# Processed a total of 5 messages
exit 0


log "Verify that the topic mirror is read-only"
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic demo"

# [2021-04-29 14:03:24,363] ERROR Error when sending message to topic demo with key: null, value: 19 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
# org.apache.kafka.common.errors.InvalidRequestException: Cannot append records to read-only mirror topic 'demo'

log "Modify the source set retention.ms"
docker container exec -i connect-us kafka-configs --alter --topic demo --add-config retention.ms=123456890 --bootstrap-server broker-us:9092

log "Check the Source Topic Configuration"
docker container exec -i connect-us kafka-configs --describe --topic demo --bootstrap-server broker-us:9092

# Dynamic configs for topic demo are:
#   retention.ms=123456890 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:retention.ms=123456890}

log "Wait 6 seconds (default is 5 minutes metadata.max.age.ms, but we modified it to 5 second)"
sleep 6

log "Check the Destination Topic Configuration"
docker container exec -i connect-us kafka-configs --describe --topic demo --bootstrap-server broker-europe:9092

# Dynamic configs for topic demo are:
#   compression.type=producer sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:compression.type=producer, DEFAULT_CONFIG:compression.type=producer}
#   cleanup.policy=delete sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:cleanup.policy=delete, DEFAULT_CONFIG:log.cleanup.policy=delete}
#   retention.ms=123456890 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:retention.ms=123456890}
#   max.message.bytes=1048588 sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:max.message.bytes=1048588, DEFAULT_CONFIG:message.max.bytes=1048588}

log "Alter the number of partitions on the source topic"
docker container exec -i connect-us kafka-topics --alter --topic demo --partitions 8 --bootstrap-server broker-us:9092

log "Verify the change on the source topic"
docker container exec -i connect-us kafka-topics --describe --topic demo --bootstrap-server broker-us:9092

log "Wait 6 seconds (default is 5 minutes metadata.max.age.ms, but we modified it to 5 second)"
sleep 6

log "Verify the change on the destination topic"
docker container exec -i connect-us kafka-topics --describe --topic demo --bootstrap-server broker-europe:9092

log "List mirror topics"
docker container exec -i connect-us kafka-cluster-links --list --link-name demo-link --include-topics --bootstrap-server broker-europe:9092
# Link name: 'demo-link', link ID: 'd80b7919-32e4-4d53-a4bb-90038b6618f4', cluster ID: 'Uz8DUGYuSVmUtwB4tBvkig', topics: [demo]

log "Cut over the mirror topic to make it writable"
docker container exec -i connect-us kafka-topics --alter --topic demo --mirror-action stop --bootstrap-server broker-europe:9092

log "Produce to both topics to verify divergence"

log "Sending data again in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo"

log "Sending data in EUROPE cluster"
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic demo"

log "Delete the cluster link"
docker container exec -i connect-us kafka-cluster-links --bootstrap-server broker-europe:9092 --delete --link-name demo-link