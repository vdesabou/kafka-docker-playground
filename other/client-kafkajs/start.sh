#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -n "$CLIENT_VERSION" ]
then
     log "📦 CLIENT_VERSION is set: building the client-kafkajs image with client version $CLIENT_VERSION"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-kafkajs container and what it depends on (broker, schema-registry): no connect, nothing to wait for
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service client-kafkajs

NB_MESSAGES=10

log "Creating topics kafkajs-string and kafkajs-avro"
playground topic create --topic kafkajs-string --nb-partitions 3
playground topic create --topic kafkajs-avro --nb-partitions 3

log "Producing $NB_MESSAGES string records with the KafkaJS producer"
playground container exec -c client-kafkajs --command "node client.js produce kafkajs-string /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the KafkaJS consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-kafkajs --command "node client.js consume kafkajs-string /tmp/client.properties $NB_MESSAGES"

log "Producing $NB_MESSAGES Avro records with the KafkaJS producer (@kafkajs/confluent-schema-registry, schema registered under subject kafkajs-avro-value)"
playground container exec -c client-kafkajs --command "node client.js produce-avro kafkajs-avro /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the KafkaJS consumer (@kafkajs/confluent-schema-registry)"
playground container exec -c client-kafkajs --command "node client.js consume-avro kafkajs-avro /tmp/client.properties $NB_MESSAGES"

log "Checking the schema registered by the KafkaJS producer (@kafkajs/confluent-schema-registry) under subject kafkajs-avro-value"
playground schema get --subject kafkajs-avro-value

log "Checking the consumer groups of the KafkaJS consumer committed the offsets"
playground consumer-group describe --group kafkajs-string-group
playground consumer-group describe --group kafkajs-avro-group
