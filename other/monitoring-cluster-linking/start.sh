#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "6.9.9"; then
    logwarn "WARN: Cluster Linking is GA since CP 7.0 only"
    exit 111
fi

${DIR}/../../environment/mdc-plaintext/start.sh "${PWD}/docker-compose.mdc-plaintext.yml"

log "Create topic purchases"
docker exec broker-us kafka-topics --create --topic purchases --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1

log "Create topic credit_cards"
docker exec broker-us kafka-topics --create --topic credit_cards --bootstrap-server broker-us:9092 --replication-factor 1 --partitions 1

log "Creating datagen-source-users connector"
docker exec -it connect-us curl -X PUT \
    -H "Content-Type: application/json" \
    --data '{
        "topics": "purchases",
        "tasks.max": "1",
        "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
        "kafka.topic": "purchases",
        "quickstart": "purchases",
        "key.converter": "org.apache.kafka.connect.storage.StringConverter",
        "key.converter.schemas.enable": "false",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",        
        "value.converter.schemas.enable": "false",
        "max.interval": 100,
        "iterations": -1
    }' \
    http://localhost:8083/connectors/datagen-source-purchases/config | jq .

log "Creating datagen-source-users connector"
docker exec -it connect-us curl -X PUT \
    -H "Content-Type: application/json" \
    --data '{
        "topics": "credit_cards",
        "tasks.max": "1",
        "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
        "kafka.topic": "credit_cards",
        "quickstart": "credit_cards",
        "key.converter": "org.apache.kafka.connect.storage.StringConverter",
        "key.converter.schemas.enable": "false",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",        
        "value.converter.schemas.enable": "false",
        "max.interval": 100,
        "iterations": -1
    }' \
    http://localhost:8083/connectors/datagen-source-credit_cards/config | jq .

log "Wait 5 seconds for some data to be generated"
sleep 5

log "Verify we have received the data in source cluster using consumer group id my-replicated-consumer-group, we read only 5 messages"
playground topic consume --topic purchases --expected-messages 5

log "Create the cluster link on the destination cluster (with metadata.max.age.ms=5 seconds + consumer.offset.sync.enable=true + consumer.offset.sync.ms=3000 + consumer.offset.sync.json set to all consumer groups)"
docker cp consumer.offset.sync.json broker-europe:/tmp/consumer.offset.sync.json
docker exec broker-europe kafka-cluster-links --bootstrap-server broker-europe:9092 --create --link link-us-to-europe --config bootstrap.servers=broker-us:9092,request.timeout.ms=2000,metadata.max.age.ms=5000,consumer.offset.sync.enable=true,consumer.offset.sync.ms=3000 --consumer-group-filters-json-file /tmp/consumer.offset.sync.json

log "Initialize the topic mirror for topic purchases"
docker exec broker-europe kafka-mirrors --create --mirror-topic purchases --link link-us-to-europe --bootstrap-server broker-europe:9092

log "Initialize the topic mirror for topic credit_cards"
docker exec broker-europe kafka-mirrors --create --mirror-topic credit_cards --link link-us-to-europe --bootstrap-server broker-europe:9092

log "Check the replica status on the destination"
docker exec broker-europe kafka-replica-status --topics purchases --include-linked --bootstrap-server broker-europe:9092

log "Wait 6 seconds for consumer.offset sync to happen (2 times consumer.offset.sync.ms=3000)"
sleep 6

log "Verify that current offset is consistent in source and destination"
log "Describe consumer group my-consumer-group at source cluster"
docker exec broker-europe kafka-consumer-groups --bootstrap-server broker-us:9092 --describe --group my-replicated-consumer-group
