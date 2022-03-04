#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh

log "Sending products in Europe cluster"
docker exec -i connect-europe bash -c "kafka-avro-console-producer --broker-list broker-europe:9092 --property schema.registry.url=http://schema-registry-europe:8081 --topic products_EUROPE --property value.schema='{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"name\",\"type\":\"string\"},
{\"name\":\"price\", \"type\": \"float\"}, {\"name\":\"quantity\", \"type\": \"int\"}]}' "<< EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF

log "Send non-avro data to trigger Unknown magic byte"
seq -f "This is a message %g" 10 | docker exec -i broker-europe kafka-console-producer --broker-list broker-europe:9092 --topic products_EUROPE


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

          "errors.log.enable": "true",
          "errors.log.include.messages": "true",
          "errors.retry.delay.max.ms": "60000",
          "errors.retry.timeout": "300000",
          "errors.tolerance": "all"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

# [2022-03-04 09:31:01,518] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Either no records were produced by the task since the last offset commit, or every record has been filtered out by a transformation or dropped due to transformation or conversion errors. (org.apache.kafka.connect.runtime.WorkerSourceTask:503)
# [2022-03-04 09:31:01,519] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic products_EUROPE to Avro: 
#         at io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:124)
#         at io.confluent.connect.replicator.ReplicatorSourceTask.convertKeyValue(ReplicatorSourceTask.java:591)
#         at io.confluent.connect.replicator.ReplicatorSourceTask.poll(ReplicatorSourceTask.java:505)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:308)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.common.errors.SerializationException: Unknown magic byte!
#         at io.confluent.kafka.serializers.AbstractKafkaSchemaSerDe.getByteBuffer(AbstractKafkaSchemaSerDe.java:250)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer$DeserializationContext.<init>(AbstractKafkaAvroDeserializer.java:322)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroDeserializer.deserializeWithSchemaAndVersion(AbstractKafkaAvroDeserializer.java:167)
#         at io.confluent.connect.avro.AvroConverter$Deserializer.deserialize(AvroConverter.java:172)
#         at io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:107)
#         ... 11 more

sleep 30

log "Verify we have received the data in topic products_EUROPE in US"
timeout 60 docker container exec -i connect-us bash -c "export CLASSPATH=/usr/share/java/monitoring-interceptors/monitoring-interceptors-${TAG_BASE}.jar; kafka-avro-console-consumer --bootstrap-server broker-us:9092 --topic products_EUROPE --from-beginning --max-messages 1 --property metadata.max.age.ms 30000 --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --consumer-property confluent.monitoring.interceptor.bootstrap.servers=broker-metrics:9092 --property schema.registry.url=http://schema-registry-us:8081"