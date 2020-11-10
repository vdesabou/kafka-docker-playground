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
          "transforms.SetSchemaMetadata.schema.name": "products-value",
          "transforms.SetSchemaMetadata.schema.version": "1"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:196)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:122)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.convertTransformedRecord(WorkerSourceTask.java:314)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:340)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:264)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.avro.SchemaParseException: Illegal character in: products-value
#         at org.apache.avro.Schema.validateName(Schema.java:1530)
#         at org.apache.avro.Schema.access$400(Schema.java:87)
#         at org.apache.avro.Schema$Name.<init>(Schema.java:673)
#         at org.apache.avro.Schema.createRecord(Schema.java:212)
#         at io.confluent.connect.avro.AvroData.fromConnectSchema(AvroData.java:867)
#         at io.confluent.connect.avro.AvroData.fromConnectSchema(AvroData.java:706)
#         at io.confluent.connect.avro.AvroData.fromConnectSchema(AvroData.java:700)
#         at io.confluent.connect.avro.AvroConverter.fromConnectData(AvroConverter.java:83)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$2(WorkerSourceTask.java:314)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:146)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:180)
#         ... 11 more

sleep 60

log "Verify we have received the data in topic products in US"
timeout 60 docker container exec -i connect-us kafka-avro-console-consumer --bootstrap-server broker-us:9092 --topic products --from-beginning --max-messages 1 --property schema.registry.url=http://schema-registry-us:8081

log "Get subject products-value version in US"
docker container exec schema-registry-us curl -X GET --silent http://localhost:8081/subjects/products-value/versions
