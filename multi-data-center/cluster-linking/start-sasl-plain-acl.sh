#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "6.9.9"; then
    logwarn "WARN: Cluster Linking is GA since CP 7.0 only"
    exit 111
fi

${DIR}/../../environment/mdc-sasl-plain/start.sh "${PWD}/docker-compose.mdc-sasl-plain-acl.yml"

log "Create topic demo"
docker exec broker-europe kafka-topics --create --topic demo --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1 --command-config /tmp/superuser-client.properties

log "Sending 20 messages in US cluster"
seq -f "us_sale_%g ${RANDOM}" 20 | docker container exec -i broker-europe bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo --producer.config /tmp/superuser-client.properties"

log "Verify we have received the data in source cluster using consumer group id my-consumer-group, we read only 5 messages"
docker container exec -i broker-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --topic demo --from-beginning --max-messages 5 --consumer-property group.id=my-consumer-group --consumer.config /tmp/superuser-client.properties"

# https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/security.html#authorization-acls
log "ACLs at Source (US)"
log "Allow DESCRIBE_CONFIGS and READ for topic demo"
docker exec broker-europe kafka-acls --bootstrap-server broker-us:9092 --add --allow-principal User:us --operation READ --topic demo --command-config /tmp/superuser-client.properties
docker exec broker-europe kafka-acls --bootstrap-server broker-us:9092 --add --allow-principal User:us --operation DescribeConfigs --topic demo --command-config /tmp/superuser-client.properties
log "Allow my-consumer-group to read and describe from topic demo"
docker exec broker-europe kafka-acls --bootstrap-server broker-us:9092 --add --allow-principal User:us --consumer --topic demo --group my-consumer-group --command-config /tmp/superuser-client.properties
log "Allow DESCRIBE cluster (for ACLs sync)"
docker exec broker-europe kafka-acls --bootstrap-server broker-us:9092 --add --allow-principal User:us --operation DESCRIBE --cluster --command-config /tmp/superuser-client.properties

log "ACLs at Destination (EUROPE)"
log "Allow DESCRIBE cluster"
docker exec broker-europe kafka-acls --bootstrap-server broker-europe:9092 --add --allow-principal User:europe --operation DESCRIBE --cluster --command-config /tmp/superuser-client.properties
log "Allow ALTER cluster"
docker exec broker-europe kafka-acls --bootstrap-server broker-europe:9092 --add --allow-principal User:europe --operation ALTER --cluster --command-config /tmp/superuser-client.properties
log "Allow CREATE for mirror topic demo"
docker exec broker-europe kafka-acls --bootstrap-server broker-europe:9092 --add --allow-principal User:europe --operation CREATE --topic demo --command-config /tmp/superuser-client.properties
log "Allow ALTER for mirror topic demo"
docker exec broker-europe kafka-acls --bootstrap-server broker-europe:9092 --add --allow-principal User:europe --operation ALTER --topic demo --command-config /tmp/superuser-client.properties
log "FIXTHIS (not documented) Allow AlterConfigs for mirror topic demo "
docker exec broker-europe kafka-acls --bootstrap-server broker-europe:9092 --add --allow-principal User:europe --operation AlterConfigs --cluster --command-config /tmp/superuser-client.properties


log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 seconds + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000 + consumer.offset.sync.json set to all consumer groups)"
docker cp consumer.offset.sync.json broker-europe:/tmp/consumer.offset.sync.json
# --config-file is for source cluster
# --command-config is for destination cluser
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link demo-link --config-file /tmp/source.config --consumer-group-filters-json-file /tmp/consumer.offset.sync.json --command-config /tmp/europe-client.properties

log "Initialize the topic mirror for topic demo"
docker exec broker-europe kafka-mirrors --create --mirror-topic demo --link demo-link --bootstrap-server broker-europe:9092 --command-config /tmp/europe-client.properties

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics demo --include-linked --bootstrap-server broker-europe:9092 --admin.config /tmp/superuser-client.properties

log "Wait 6 seconds for consumer.offset sync to happen (2 times consumer.offset.sync.ms=3000)"
sleep 6

log "Verify that current offset is consistent in source and destination"
log "Describe consumer group my-consumer-group at Source cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group my-consumer-group --command-config /tmp/superuser-client.properties

log "Describe consumer group my-consumer-group at Destination cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group --command-config /tmp/superuser-client.properties

log "Consume from the mirror topic on the destination cluster and verify consumer offset is working, it should start at 6"
docker container exec -i broker-europe bash -c "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic demo --max-messages 5 --consumer-property group.id=my-consumer-group --consumer.config /tmp/superuser-client.properties"

log "Describe consumer group my-consumer-group at Destination cluster."
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group --command-config /tmp/superuser-client.properties
log "sleep 6 seconds"
sleep 6
log "Describe consumer group my-consumer-group at Destination cluster. Note: the current-offset has been overwritten due to the consumer offset sync"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-europe:9092 --describe --group my-consumer-group --command-config /tmp/superuser-client.properties

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
docker exec broker-europe kafka-configs --bootstrap-server broker-europe:9092 --alter --cluster-link demo-link --add-config-file /tmp/newFilters.properties --command-config /tmp/europe-client.properties

sleep 6

log "Consume from the source cluster another 10 messages, up to 15"
docker container exec -i broker-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --topic demo --max-messages 10 --consumer-property group.id=my-consumer-group --consumer.config /tmp/superuser-client.properties"

log "Consume from the destination cluster, it will continue from it's last offset 10"
docker container exec -i broker-europe bash -c "kafka-console-consumer --bootstrap-server broker-europe:9092 --topic demo --max-messages 5 --consumer-property group.id=my-consumer-group --consumer.config /tmp/superuser-client.properties"

log "Verify that the topic mirror is read-only"
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic demo --producer.config /tmp/superuser-client.properties"

log "Modify the source topic config, set retention.ms"
docker container exec -i broker-europe kafka-configs --alter --topic demo --add-config retention.ms=123456890 --bootstrap-server broker-us:9092 --command-config /tmp/superuser-client.properties

log "Check the Source Topic Configuration"
docker container exec -i broker-europe kafka-configs --describe --topic demo --bootstrap-server broker-us:9092 --command-config /tmp/superuser-client.properties

log "Wait 6 seconds (default is 5 minutes metadata.max.age.ms, but we modified it to 5 seconds)"
sleep 6

log "Check the Destination Topic Configuration"
docker container exec -i broker-europe kafka-configs --describe --topic demo --bootstrap-server broker-europe:9092 --command-config /tmp/superuser-client.properties

log "Alter the number of partitions on the source topic"
docker container exec -i broker-europe kafka-topics --alter --topic demo --partitions 8 --bootstrap-server broker-us:9092 --command-config /tmp/superuser-client.properties

log "Verify the change on the source topic"
docker container exec -i broker-europe kafka-topics --describe --topic demo --bootstrap-server broker-us:9092 --command-config /tmp/superuser-client.properties

log "Wait 6 seconds (default is 5 minutes metadata.max.age.ms, but we modified it to 5 seconds)"
sleep 6

log "Verify the change on the destination topic"
docker container exec -i broker-europe kafka-topics --describe --topic demo --bootstrap-server broker-europe:9092 --command-config /tmp/superuser-client.properties

log "List mirror topics"
docker container exec -i broker-europe kafka-cluster-links --list --link demo-link --include-topics --bootstrap-server broker-europe:9092 --command-config /tmp/superuser-client.properties

log "Cut over the mirror topic to make it writable"
docker container exec -i broker-europe kafka-mirrors --promote --topics demo --bootstrap-server broker-europe:9092 --command-config /tmp/superuser-client.properties

log "Produce to both topics to verify divergence"

log "Sending data again in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe bash -c "kafka-console-producer --broker-list broker-us:9092 --topic demo --producer.config /tmp/superuser-client.properties"

log "Sending data in EUROPE cluster"
seq -f "europe_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic demo --producer.config /tmp/superuser-client.properties"

set +e
log "Delete the cluster link"
docker container exec -i broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --delete --link demo-link --command-config /tmp/superuser-client.properties

exit 0