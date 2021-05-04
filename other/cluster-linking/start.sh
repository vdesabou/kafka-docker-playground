#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Create topic demo"
docker exec broker-europe kafka-topics --create --topic demo --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i connect-us bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo"

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --topic demo --from-beginning --max-messages 10"

log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 minutes + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000)"
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link-name demo-link --config bootstrap.servers=broker-us:9092,metadata.max.age.ms=5000

#,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000

log "Initialize the topic mirror"
docker exec broker-europe kafka-topics --create --topic demo --mirror-topic demo --link-name demo-link --bootstrap-server broker-europe:9092

log "Consume from the mirror topic on the destination cluster to verify it"
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic demo --from-beginning --max-messages 10"

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092

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