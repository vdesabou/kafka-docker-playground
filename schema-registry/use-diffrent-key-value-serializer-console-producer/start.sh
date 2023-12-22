#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment plaintext

log "Create a topic my-topic"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic my-topic --partitions 1

log "Produce records to my-topic with --property key.serializer="
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property parse.key=true --property key.separator=":" --property key.serializer=org.apache.kafka.common.serialization.StringSerializer  << EOF
"test-key1":{"f1": "value1"}
"test-key2":{"f1": "value2"}
EOF

log "Consuming records from this topic with key.deserializer=org.apache.kafka.common.serialization.StringDeserializer"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 \
    --topic my-topic  --from-beginning \
    --property schema.registry.url=http://schema-registry:8081 --property print.key=true --property print.schema.ids=true  --property schema.id.separator=:  --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer  \
    --max-messages 2
