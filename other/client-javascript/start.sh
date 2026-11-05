#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -n "$CLIENT_VERSION" ]
then
     log "📦 CLIENT_VERSION is set: building the client-javascript image with client version $CLIENT_VERSION"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-javascript container and what it depends on (broker, schema-registry): no connect, nothing to wait for
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service client-javascript

NB_MESSAGES=10

log "Creating topics javascript-string and javascript-avro"
playground topic create --topic javascript-string --nb-partitions 3
playground topic create --topic javascript-avro --nb-partitions 3

log "Producing $NB_MESSAGES string records with the JavaScript producer"
playground container exec -c client-javascript --command "node client.js produce javascript-string /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the JavaScript consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-javascript --command "node client.js consume javascript-string /tmp/client.properties $NB_MESSAGES"

log "Producing $NB_MESSAGES Avro records with the JavaScript producer (AvroSerializer, schema registered under subject javascript-avro-value)"
playground container exec -c client-javascript --command "node client.js produce-avro javascript-avro /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the JavaScript consumer (AvroDeserializer)"
playground container exec -c client-javascript --command "node client.js consume-avro javascript-avro /tmp/client.properties $NB_MESSAGES"

log "Checking the schema registered by the JavaScript AvroSerializer under subject javascript-avro-value"
playground schema get --subject javascript-avro-value

log "Checking the consumer groups of the JavaScript consumer committed the offsets"
playground consumer-group describe --group javascript-string-group
playground consumer-group describe --group javascript-avro-group
