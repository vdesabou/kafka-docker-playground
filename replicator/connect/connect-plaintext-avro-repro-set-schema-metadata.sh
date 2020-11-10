#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh

log "Register a subject in US cluster with id 1"
docker container exec schema-registry-us \
curl -X POST --silent http://localhost:8081/subjects/products_EUROPE-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\n    \"fields\": [\n      {\n        \"name\": \"id\",\n        \"type\": \"long\"\n      },\n      {\n        \"default\": null,\n        \"name\": \"first_name\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"last_name\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"email\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"gender\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"ip_address\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"last_login\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"account_balance\",\n        \"type\": [\n          \"null\",\n          {\n            \"logicalType\": \"decimal\",\n            \"precision\": 64,\n            \"scale\": 2,\n            \"type\": \"bytes\"\n          }\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"country\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      },\n      {\n        \"default\": null,\n        \"name\": \"favorite_color\",\n        \"type\": [\n          \"null\",\n          \"string\"\n        ]\n      }\n    ],\n    \"name\": \"User\",\n    \"namespace\": \"com.example.users\",\n    \"type\": \"record\"\n  }"
}'

log "Sending products in Europe cluster"
docker exec -i connect-europe bash -c "kafka-avro-console-producer --broker-list broker-europe:9092 --property schema.registry.url=http://schema-registry-europe:8081 --topic products_EUROPE --property value.schema='{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"name\",\"type\":\"string\"},
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
          "src.consumer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
          "src.consumer.confluent.monitoring.interceptor.bootstrap.servers": "broker-metrics:9092",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "src.value.converter": "io.confluent.connect.avro.AvroConverter",
          "src.value.converter.schema.registry.url": "http://schema-registry-europe:8081",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "products_EUROPE",
          "transforms": "SetSchemaMetadata",
          "transforms.SetSchemaMetadata.type": "org.apache.kafka.connect.transforms.SetSchemaMetadata$Value",
          "transforms.SetSchemaMetadata.schema.name": "products_EUROPE",
          "transforms.SetSchemaMetadata.schema.version": "1"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .


sleep 30

log "Verify we have received the data in topic products_EUROPE in US"
timeout 60 docker container exec -i connect-us bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-avro-console-consumer --bootstrap-server broker-us:9092 --topic products_EUROPE --from-beginning --max-messages 1 --property metadata.max.age.ms 30000 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092 --property schema.registry.url=http://schema-registry-us:8081"

log "Get subject version"
docker container exec schema-registry-us curl -X GET --silent http://localhost:8081/subjects/products_EUROPE-value/versions


# [2020-11-10 15:32:55,833] ERROR WorkerSourceTask{id=replicate-europe-to-us-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
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
# Caused by: org.apache.kafka.connect.errors.DataException: Failed to serialize Avro data from topic products_EUROPE :
#         at io.confluent.connect.avro.AvroConverter.fromConnectData(AvroConverter.java:91)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$2(WorkerSourceTask.java:314)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:146)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:180)
#         ... 11 more
# Caused by: org.apache.kafka.common.errors.SerializationException: Error registering Avro schema: {"type":"record","name":"products_EUROPE","fields":[{"name":"name","type":"string"},{"name":"price","type":"float"},{"name":"quantity","type":"int"}]}
# Caused by: io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: Schema being registered is incompatible with an earlier schema for subject "products_EUROPE-value"; error code: 409
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.sendHttpRequest(RestService.java:292)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.httpRequest(RestService.java:352)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:495)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:486)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:459)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.registerAndGetId(CachedSchemaRegistryClient.java:206)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:268)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:244)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:75)
#         at io.confluent.connect.avro.AvroConverter$Serializer.serialize(AvroConverter.java:143)
#         at io.confluent.connect.avro.AvroConverter.fromConnectData(AvroConverter.java:84)
#         at org.apache.kafka.connect.storage.Converter.fromConnectData(Converter.java:63)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.lambda$convertTransformedRecord$2(WorkerSourceTask.java:314)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:146)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:180)
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