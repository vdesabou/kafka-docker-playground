#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh

log "Create topic sales_EUROPE in EUROPE with config confluent.value.schema.validation=true"
docker exec broker-europe kafka-topics --create --topic sales_EUROPE --partitions 1 --replication-factor 1 --bootstrap-server broker-europe:9092 --config confluent.value.schema.validation=true

# same issue if topic is pre-created and "topic.config.sync": "false"
# log "Create topic sales_EUROPE in US with config confluent.value.schema.validation=true"
# docker exec broker-us kafka-topics --create --topic sales_EUROPE --partitions 1 --replication-factor 1 --bootstrap-server broker-us:9092 --config confluent.value.schema.validation=true


log "Sending sales in Europe cluster"
docker exec -i connect-europe kafka-avro-console-producer --broker-list broker-europe:9092 --property schema.registry.url=http://schema-registry-europe:8081 --topic sales_EUROPE --property key.schema='{"type":"record","namespace": "io.confluent.connect.avro","name":"myrecordkey","fields":[{"name":"ID","type":"long"}]}' --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
{"ID": 111}|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
{"ID": 222}|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF

log "Create replicator"
# docker container exec connect-us \
# curl -X PUT \
#      -H "Content-Type: application/json" \
#      --data '{
#           "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
#           "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
#           "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
#           "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
#           "src.consumer.group.id": "replicate-europe-to-us",
#           "src.consumer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
#           "src.consumer.confluent.monitoring.interceptor.bootstrap.servers": "broker-metrics:9092",
#           "src.kafka.bootstrap.servers": "broker-europe:9092",
#           "dest.kafka.bootstrap.servers": "broker-us:9092",
#           "confluent.topic.replication.factor": 1,
#           "provenance.header.enable": true,
#           "topic.whitelist": "sales_EUROPE",
#           "topic.config.sync": "true"
#           }' \
#      http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

# working with avroconverter

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
          "topic.whitelist": "sales_EUROPE",
          "topic.config.sync": "true"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .
     

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i connect-us bash -c "kafka-avro-console-consumer --bootstrap-server broker-us:9092 --property schema.registry.url=http://schema-registry-us:8081 --whitelist 'sales_.*' --from-beginning --property print.key=true --property key.separator=, --max-messages 2"


log "Verify the destination topic has confluent.value.schema.validation=true"
docker container exec -i broker-us kafka-topics --describe --topic sales_EUROPE --bootstrap-server broker-us:9092

# Topic: sales_EUROPE     PartitionCount: 1       ReplicationFactor: 1    Configs: confluent.value.schema.validation=true,message.timestamp.type=CreateTime
#         Topic: sales_EUROPE     Partition: 0    Leader: 2       Replicas: 2     Isr: 2  Offline: 

# With 7.0.1

# [2022-02-02 10:35:52,832] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:384)
# org.apache.kafka.common.InvalidRecordException: Log record DefaultRecord(offset=0, timestamp=1643798150113, key=7 bytes, value=17 bytes) is rejected by the record interceptor io.confluent.kafka.schemaregistry.validator.RecordSchemaValidator
# [2022-02-02 10:35:52,834] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer-us] Cluster ID: 3e5GM-S0QAqzBVcgwq3tRQ (org.apache.kafka.clients.Metadata:287)
# [2022-02-02 10:35:52,840] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:384)
# org.apache.kafka.common.InvalidRecordException: Log record DefaultRecord(offset=0, timestamp=1643798150125, key=7 bytes, value=17 bytes) is rejected by the record interceptor io.confluent.kafka.schemaregistry.validator.RecordSchemaValidator


# With 6.1.0
# [2022-02-02 10:25:06,700] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:370)
# org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-02-02 10:25:06,701] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer-us] Cluster ID: AE59TlymS0qIfYC_mLUDjg (org.apache.kafka.clients.Metadata:279)
# [2022-02-02 10:25:06,704] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:370)
# org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-02-02 10:25:36,363] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:478)
# [2022-02-02 10:25:36,364] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 2 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:495)
# [2022-02-02 10:25:41,364] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 2 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:500)
[2022-02-02 10:25:41,364] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:187)
org.apache.kafka.connect.errors.ConnectException: Unrecoverable exception from producer send callback
        at org.apache.kafka.connect.runtime.WorkerSourceTask.maybeThrowProducerSendException(WorkerSourceTask.java:282)
        at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:251)
        at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
        at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
        at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
        at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
        at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
        at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
        at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-02-02 10:25:41,365] INFO [replicate-europe-to-us|task-0] Closing kafka replicator task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:1187)
# [2022-02-02 10:25:41,365] INFO [replicate-europe-to-us|task-0] App info kafka.admin.client for adminclient-17 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:25:41,366] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,366] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,366] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,367] INFO [replicate-europe-to-us|task-0] App info kafka.admin.client for adminclient-16 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:25:41,368] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,368] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,368] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,369] INFO [replicate-europe-to-us|task-0] Publish thread interrupted for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=J4bkzR25Q5Gpvo9_HNKIDA group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-02-02 10:25:41,369] INFO [replicate-europe-to-us|task-0] Publishing Monitoring Metrics stopped for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=J4bkzR25Q5Gpvo9_HNKIDA group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-02-02 10:25:41,369] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.replicate-europe-to-us-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-02-02 10:25:41,373] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,373] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,373] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,374] INFO [replicate-europe-to-us|task-0] App info kafka.producer for confluent.monitoring.interceptor.replicate-europe-to-us-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:25:41,374] INFO [replicate-europe-to-us|task-0] Closed monitoring interceptor for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=J4bkzR25Q5Gpvo9_HNKIDA group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-02-02 10:25:41,374] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,374] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,375] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,376] INFO [replicate-europe-to-us|task-0] App info kafka.consumer for replicate-europe-to-us-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:25:41,377] INFO [replicate-europe-to-us|task-0] [Producer clientId=producer-6] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-02-02 10:25:41,378] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,378] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,378] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,378] INFO [replicate-europe-to-us|task-0] App info kafka.producer for producer-6 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:25:41,379] INFO [replicate-europe-to-us|task-0] Shutting down metrics recording for task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:1209)
# [2022-02-02 10:25:41,387] INFO [replicate-europe-to-us|task-0] Unregistering Confluent Replicator metrics with JMX for task 'replicate-europe-to-us-0' (io.confluent.connect.replicator.metrics.ConfluentReplicatorMetrics:86)
# [2022-02-02 10:25:41,387] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,387] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,387] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,388] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,388] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,388] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,390] INFO [replicate-europe-to-us|task-0] App info kafka.consumer for confluent-replicator-end-offsets-consumer-client unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:25:41,391] INFO [replicate-europe-to-us|task-0] [Producer clientId=connect-worker-producer-us] Closing the Kafka producer with timeoutMillis = 30000 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-02-02 10:25:41,392] INFO [replicate-europe-to-us|task-0] Publish thread interrupted for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=1955-MeZS0y7gMMpMeQeJQ (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-02-02 10:25:41,392] INFO [replicate-europe-to-us|task-0] Publishing Monitoring Metrics stopped for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=1955-MeZS0y7gMMpMeQeJQ (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-02-02 10:25:41,392] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer-us] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-02-02 10:25:41,393] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,393] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,394] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,394] INFO [replicate-europe-to-us|task-0] App info kafka.producer for confluent.monitoring.interceptor.connect-worker-producer-us unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:25:41,394] INFO [replicate-europe-to-us|task-0] Closed monitoring interceptor for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=1955-MeZS0y7gMMpMeQeJQ (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-02-02 10:25:41,394] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-02-02 10:25:41,394] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-02-02 10:25:41,394] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-02-02 10:25:41,394] INFO [replicate-europe-to-us|task-0] App info kafka.producer for connect-worker-producer-us unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-02-02 10:26:06,316] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:478)
# [2022-02-02 10:26:06,317] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 2 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:495)
# [2022-02-02 10:26:11,316] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 2 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:500)
# [2022-02-02 10:26:11,316] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
