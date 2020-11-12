#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh

log "Register a subject in US cluster with version 1 (default for quantity=1)"
docker container exec schema-registry-us \
curl -X POST --silent http://localhost:8081/subjects/products-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\n  \"fields\": [\n    {\n      \"name\": \"name\",\n      \"type\": \"string\"\n    },\n    {\n      \"name\": \"price\",\n      \"type\": \"float\"\n    },\n    {\n      \"name\": \"quantity\",\n      \"type\": \"int\"\n, \"default\": 1    }\n  ],\n  \"name\": \"myrecord\",\n  \"type\": \"record\"\n}"
}'

log "Register a subject in US cluster with version 2 (default for quantity=2)"
docker container exec schema-registry-us \
curl -X POST --silent http://localhost:8081/subjects/products-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\n  \"fields\": [\n    {\n      \"name\": \"name\",\n      \"type\": \"string\"\n    },\n    {\n      \"name\": \"price\",\n      \"type\": \"float\"\n    },\n    {\n      \"name\": \"quantity\",\n      \"type\": \"int\"\n, \"default\": 2    }\n  ],\n  \"name\": \"myrecord\",\n  \"type\": \"record\"\n}"
}'

log "Get subject products-value version in US"
docker container exec schema-registry-us curl -X GET --silent http://localhost:8081/subjects/products-value/versions

log "Sending products in Europe cluster  (default for quantity=3)"
docker exec -i connect-europe bash -c "kafka-avro-console-producer --broker-list broker-europe:9092 --property schema.registry.url=http://schema-registry-europe:8081 --topic products --property value.schema='{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"name\",\"type\":\"string\"},
{\"name\":\"price\", \"type\": \"float\"}, {\"name\":\"quantity\", \"type\": \"int\", \"default\": 3}]}' "<< EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF

log "Replicate topic products from Europe to US using AvroConverter"
docker container exec connect-us \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry-us:8081",
          "value.converter.connect.meta.data": "false",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.consumer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
          "src.consumer.confluent.monitoring.interceptor.bootstrap.servers": "broker-metrics:9092",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "src.value.converter": "io.confluent.connect.avro.AvroConverter",
          "src.value.converter.schema.registry.url": "http://schema-registry-europe:8081",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "products",
          "transforms": "SetSchemaMetadata",
          "transforms.SetSchemaMetadata.type": "org.apache.kafka.connect.transforms.SetSchemaMetadata$Value",
          "transforms.SetSchemaMetadata.schema.name": "myrecord",
          "transforms.SetSchemaMetadata.schema.version": "1"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

sleep 60

log "Verify we have received the data in topic products in US"
timeout 60 docker container exec connect-us kafka-avro-console-consumer --bootstrap-server broker-us:9092 --topic products --from-beginning --max-messages 1 --property schema.registry.url=http://schema-registry-us:8081

log "Get subject products-value version in US"
docker container exec schema-registry-us curl -X GET --silent http://localhost:8081/subjects/products-value/versions
