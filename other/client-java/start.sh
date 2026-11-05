#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -n "$CLIENT_VERSION" ]
then
     log "📦 CLIENT_VERSION is set: building the client-java image with client version $CLIENT_VERSION"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
# only the client-java container and what it depends on (broker, schema-registry): no connect, nothing to wait for
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml" --service client-java

NB_MESSAGES=10

log "Creating topics java-string and java-avro"
playground topic create --topic java-string --nb-partitions 3
playground topic create --topic java-avro --nb-partitions 3

log "Producing $NB_MESSAGES string records with the Java producer"
playground container exec -c client-java --command "java -jar client-java.jar produce java-string /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the Java consumer, it fails if fewer than $NB_MESSAGES records arrive within 60 seconds"
playground container exec -c client-java --command "java -jar client-java.jar consume java-string /tmp/client.properties $NB_MESSAGES"

log "Producing $NB_MESSAGES Avro records with the Java producer (KafkaAvroSerializer, schema registered under subject java-avro-value)"
playground container exec -c client-java --command "java -jar client-java.jar produce-avro java-avro /tmp/client.properties $NB_MESSAGES"

log "Consuming them with the Java consumer (KafkaAvroDeserializer)"
playground container exec -c client-java --command "java -jar client-java.jar consume-avro java-avro /tmp/client.properties $NB_MESSAGES"

log "Checking the schema registered by the KafkaAvroSerializer under subject java-avro-value"
playground schema get --subject java-avro-value

log "Checking the consumer groups of the Java consumer committed the offsets"
playground consumer-group describe --group java-string-group
playground consumer-group describe --group java-avro-group
