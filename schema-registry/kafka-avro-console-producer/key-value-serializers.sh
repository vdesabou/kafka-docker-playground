#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

playground topic create --topic my-topic --nb-partitions 1

log "Produce 2 records with kafka-avro-console-producer: String key (key.serializer=StringSerializer), Avro value"
playground container exec -c connect --command "kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my-topic --property value.schema='{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"f1\",\"type\":\"string\"}]}' --property parse.key=true --property key.separator=: --property key.serializer=org.apache.kafka.common.serialization.StringSerializer" << 'EOF2'
test-key1:{"f1": "value1"}
test-key2:{"f1": "value2"}
EOF2

log "Consume them with kafka-avro-console-consumer and key.deserializer=StringDeserializer"
playground container exec -c connect --command "kafka-avro-console-consumer --bootstrap-server broker:9092 --topic my-topic --from-beginning --property schema.registry.url=http://schema-registry:8081 --property print.key=true --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --max-messages 2"

log "Check that the 2 records have a String key and an Avro value"
playground topic consume --topic my-topic --min-expected-messages 2 --timeout 60
