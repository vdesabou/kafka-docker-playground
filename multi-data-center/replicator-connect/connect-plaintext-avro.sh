#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "$PWD/docker-compose.mdc-plaintext.yml"

log "Sending products in Europe cluster"
docker exec -i connect-europe bash -c "kafka-avro-console-producer --bootstrap-server broker-europe:9092 --property schema.registry.url=http://schema-registry-europe:8081 --topic products_EUROPE --property value.schema='{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"name\",\"type\":\"string\"},
{\"name\":\"price\", \"type\": \"float\"}, {\"name\":\"quantity\", \"type\": \"int\"}]}' "<< EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF

log "Replicate topic products_EUROPE from Europe to US using AvroConverter"
docker container exec connect-us \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry-us:8081",
          "value.converter.connect.meta.data": "false",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "src.value.converter": "io.confluent.connect.avro.AvroConverter",
          "src.value.converter.schema.registry.url": "http://schema-registry-europe:8081",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "products_EUROPE"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .


sleep 30

log "Verify we have received the data in topic products_EUROPE in US"
timeout 60 docker container exec -i connect-us bash -c "kafka-avro-console-consumer --bootstrap-server broker-us:9092 --topic products_EUROPE --from-beginning --max-messages 1 --property metadata.max.age.ms 30000 --property schema.registry.url=http://schema-registry-us:8081"