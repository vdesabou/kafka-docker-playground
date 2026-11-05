#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-go container and what it depends on (broker, schema-registry): no connect, nothing to wait for
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service client-go

NB_MESSAGES=10

log "Creating topics go-string and go-avro"
playground topic create --topic go-string --nb-partitions 3
playground topic create --topic go-avro --nb-partitions 3

log "Producing $NB_MESSAGES string records with the Go producer"
playground container exec -c client-go --command "client produce go-string /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the Go consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-go --command "client consume go-string /tmp/client.properties $NB_MESSAGES"

log "Producing $NB_MESSAGES Avro records with the Go producer (avrov2 serializer, schema registered under subject go-avro-value)"
playground container exec -c client-go --command "client produce-avro go-avro /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the Go consumer (avrov2 deserializer)"
playground container exec -c client-go --command "client consume-avro go-avro /tmp/client.properties $NB_MESSAGES"

log "Checking the schema registered by the Go avrov2 serializer under subject go-avro-value"
playground schema get --subject go-avro-value

log "Checking the consumer groups of the Go consumer committed the offsets"
playground consumer-group describe --group go-string-group
playground consumer-group describe --group go-avro-group
