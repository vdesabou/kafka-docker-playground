#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh

log "Create topic sales_EUROPE in europe with cleanup.policy=delete"
docker exec broker-europe kafka-topics --create --topic sales_EUROPE --partitions 1 --replication-factor 1 --bootstrap-server broker-europe:9092 --config cleanup.policy=delete
log "Sending sales in Europe cluster with no key"
docker exec -i broker-europe kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE << EOF
value1
value2
value3
EOF

log "Create topic sales_EUROPE in US with cleanup.policy=compact"
docker exec broker-us kafka-topics --create --topic sales_EUROPE --partitions 1 --replication-factor 1 --bootstrap-server broker-us:9092 --config cleanup.policy=compact

log "Create replicator"
docker container exec connect-us \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.consumer.interceptor.classes": "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor",
          "src.consumer.confluent.monitoring.interceptor.bootstrap.servers": "broker-metrics:9092",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE",
          "topic.config.sync": "false"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .


sleep 15

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i connect-us bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_.*' --from-beginning --property print.key=true --property key.separator=, --max-messages 3"

# [2022-01-18 16:01:44,683] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:372)
# org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-01-18 16:01:44,686] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:372)
# org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-01-18 16:02:14,540] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:02:14,540] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:02:19,540] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:02:19,541] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:191)
# org.apache.kafka.connect.errors.ConnectException: Unrecoverable exception from producer send callback
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.maybeThrowProducerSendException(WorkerSourceTask.java:284)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:243)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-01-18 16:02:19,541] INFO [replicate-europe-to-us|task-0] Closing kafka replicator task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:1195)
# [2022-01-18 16:02:19,542] INFO [replicate-europe-to-us|task-0] App info kafka.admin.client for adminclient-13 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:19,543] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,543] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,543] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,544] INFO [replicate-europe-to-us|task-0] App info kafka.admin.client for adminclient-12 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:19,544] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,545] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,545] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,545] INFO [replicate-europe-to-us|task-0] Publish thread interrupted for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=XesYUUWaRr2NKrPXROZFvQ group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-01-18 16:02:19,546] INFO [replicate-europe-to-us|task-0] Publishing Monitoring Metrics stopped for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=XesYUUWaRr2NKrPXROZFvQ group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-01-18 16:02:19,546] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.replicate-europe-to-us-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:02:19,548] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,549] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,549] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,549] INFO [replicate-europe-to-us|task-0] App info kafka.producer for confluent.monitoring.interceptor.replicate-europe-to-us-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:19,549] INFO [replicate-europe-to-us|task-0] Closed monitoring interceptor for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=XesYUUWaRr2NKrPXROZFvQ group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-01-18 16:02:19,549] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,549] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,549] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,550] INFO [replicate-europe-to-us|task-0] App info kafka.consumer for replicate-europe-to-us-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:19,550] INFO [replicate-europe-to-us|task-0] [Producer clientId=producer-5] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:02:19,551] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] App info kafka.producer for producer-5 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] Shutting down metrics recording for task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:1217)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] Unregistering Confluent Replicator metrics with JMX for task 'replicate-europe-to-us-0' (io.confluent.connect.replicator.metrics.ConfluentReplicatorMetrics:86)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,552] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,553] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,553] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,553] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,554] INFO [replicate-europe-to-us|task-0] App info kafka.consumer for confluent-replicator-end-offsets-consumer-client unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:19,554] INFO [replicate-europe-to-us|task-0] [Producer clientId=connect-worker-producer-us] Closing the Kafka producer with timeoutMillis = 30000 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:02:19,555] INFO [replicate-europe-to-us|task-0] Publish thread interrupted for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-01-18 16:02:19,556] INFO [replicate-europe-to-us|task-0] Publishing Monitoring Metrics stopped for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-01-18 16:02:19,556] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer-us] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] App info kafka.producer for confluent.monitoring.interceptor.connect-worker-producer-us unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] Closed monitoring interceptor for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:02:19,557] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:02:19,558] INFO [replicate-europe-to-us|task-0] App info kafka.producer for connect-worker-producer-us unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:02:44,201] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:02:44,201] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:02:49,202] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:02:49,202] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:03:44,130] INFO [replicate-europe-to-us|worker] Found matching topics: [__consumer_timestamps, sales_EUROPE] (io.confluent.connect.replicator.NewTopicMonitorThread:329)
# [2022-01-18 16:03:44,133] INFO SourceConnectorConfig values: 
#         config.action.reload = restart
#         connector.class = io.confluent.connect.replicator.ReplicatorSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         name = replicate-europe-to-us
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (org.apache.kafka.connect.runtime.SourceConnectorConfig:361)
# [2022-01-18 16:03:44,134] INFO EnrichedConnectorConfig values: 
#         config.action.reload = restart
#         connector.class = io.confluent.connect.replicator.ReplicatorSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         name = replicate-europe-to-us
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig:361)
# [2022-01-18 16:03:44,134] INFO [replicate-europe-to-us|worker] Gathering task configs... (io.confluent.connect.replicator.ReplicatorSourceConnector:110)
# [2022-01-18 16:03:44,134] INFO [replicate-europe-to-us|worker] Assigning topic partitions to 1 tasks... (io.confluent.connect.replicator.NewTopicMonitorThread:149)
# [2022-01-18 16:03:44,135] INFO [replicate-europe-to-us|worker] Finished computing task topic partition assignments: {replicate-europe-to-us-0=Assignment(partitions=[__consumer_timestamps-0, __consumer_timestamps-1, __consumer_timestamps-2, __consumer_timestamps-3, __consumer_timestamps-4, __consumer_timestamps-5, __consumer_timestamps-6, __consumer_timestamps-7, __consumer_timestamps-8, __consumer_timestamps-9, __consumer_timestamps-10, __consumer_timestamps-11, __consumer_timestamps-12, __consumer_timestamps-13, __consumer_timestamps-14, __consumer_timestamps-15, __consumer_timestamps-16, __consumer_timestamps-17, __consumer_timestamps-18, __consumer_timestamps-19, __consumer_timestamps-20, __consumer_timestamps-21, __consumer_timestamps-22, __consumer_timestamps-23, __consumer_timestamps-24, __consumer_timestamps-25, __consumer_timestamps-26, __consumer_timestamps-27, __consumer_timestamps-28, __consumer_timestamps-29, __consumer_timestamps-30, __consumer_timestamps-31, __consumer_timestamps-32, __consumer_timestamps-33, __consumer_timestamps-34, __consumer_timestamps-35, __consumer_timestamps-36, __consumer_timestamps-37, __consumer_timestamps-38, __consumer_timestamps-39, __consumer_timestamps-40, __consumer_timestamps-41, __consumer_timestamps-42, __consumer_timestamps-43, __consumer_timestamps-44, __consumer_timestamps-45, __consumer_timestamps-46, __consumer_timestamps-47, __consumer_timestamps-48, __consumer_timestamps-49, sales_EUROPE-0])} (io.confluent.connect.replicator.NewTopicMonitorThread:184)
# [2022-01-18 16:03:44,135] INFO [replicate-europe-to-us|worker] ReplicatorSourceTaskConfig values: 
#         confluent.license = 
#         confluent.topic = _confluent-command
#         dest.kafka.bootstrap.servers = [broker-us:9092]
#         dest.kafka.client.id = 
#         dest.kafka.connections.max.idle.ms = 540000
#         dest.kafka.metric.reporters = []
#         dest.kafka.metrics.num.samples = 2
#         dest.kafka.metrics.sample.window.ms = 30000
#         dest.kafka.receive.buffer.bytes = 65536
#         dest.kafka.reconnect.backoff.ms = 50
#         dest.kafka.request.timeout.ms = 30000
#         dest.kafka.retry.backoff.ms = 100
#         dest.kafka.sasl.client.callback.handler.class = null
#         dest.kafka.sasl.jaas.config = null
#         dest.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         dest.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         dest.kafka.sasl.kerberos.service.name = null
#         dest.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         dest.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         dest.kafka.sasl.login.callback.handler.class = null
#         dest.kafka.sasl.login.class = null
#         dest.kafka.sasl.login.refresh.buffer.seconds = 300
#         dest.kafka.sasl.login.refresh.min.period.seconds = 60
#         dest.kafka.sasl.login.refresh.window.factor = 0.8
#         dest.kafka.sasl.login.refresh.window.jitter = 0.05
#         dest.kafka.sasl.mechanism = GSSAPI
#         dest.kafka.security.protocol = PLAINTEXT
#         dest.kafka.send.buffer.bytes = 131072
#         dest.kafka.ssl.cipher.suites = null
#         dest.kafka.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         dest.kafka.ssl.endpoint.identification.algorithm = https
#         dest.kafka.ssl.engine.factory.class = null
#         dest.kafka.ssl.key.password = null
#         dest.kafka.ssl.keymanager.algorithm = SunX509
#         dest.kafka.ssl.keystore.certificate.chain = null
#         dest.kafka.ssl.keystore.key = null
#         dest.kafka.ssl.keystore.location = null
#         dest.kafka.ssl.keystore.password = null
#         dest.kafka.ssl.keystore.type = JKS
#         dest.kafka.ssl.protocol = TLSv1.3
#         dest.kafka.ssl.provider = null
#         dest.kafka.ssl.secure.random.implementation = null
#         dest.kafka.ssl.trustmanager.algorithm = PKIX
#         dest.kafka.ssl.truststore.certificates = null
#         dest.kafka.ssl.truststore.location = null
#         dest.kafka.ssl.truststore.password = null
#         dest.kafka.ssl.truststore.type = JKS
#         dest.topic.replication.factor = 0
#         dest.zookeeper.connect = 
#         dest.zookeeper.connection.timeout.ms = 6000
#         dest.zookeeper.session.timeout.ms = 6000
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         offset.start = connect
#         offset.timestamps.commit = true
#         offset.topic.commit = true
#         offset.translator.batch.period.ms = 60000
#         offset.translator.batch.size = 1
#         offset.translator.tasks.max = -1
#         offset.translator.tasks.separate = false
#         partition.assignment = AAEAAAACABVfX2NvbnN1bWVyX3RpbWVzdGFtcHMAAAAyAAAAAAAAAAEAAAACAAAAAwAAAAQAAAAFAAAABgAAAAcAAAAIAAAACQAAAAoAAAALAAAADAAAAA0AAAAOAAAADwAAABAAAAARAAAAEgAAABMAAAAUAAAAFQAAABYAAAAXAAAAGAAAABkAAAAaAAAAGwAAABwAAAAdAAAAHgAAAB8AAAAgAAAAIQAAACIAAAAjAAAAJAAAACUAAAAmAAAAJwAAACgAAAApAAAAKgAAACsAAAAsAAAALQAAAC4AAAAvAAAAMAAAADEADHNhbGVzX0VVUk9QRQAAAAEAAAAA/////w==
#         provenance.header.enable = true
#         provenance.header.filter.overrides = 
#         schema.registry.client.basic.auth.credentials.source = URL
#         schema.registry.client.basic.auth.user.info = [hidden]
#         schema.registry.max.schemas.per.subject = 1000
#         schema.registry.topic = null
#         schema.registry.url = null
#         schema.subject.translator.class = null
#         src.consumer.check.crcs = true
#         src.consumer.fetch.max.bytes = 52428800
#         src.consumer.fetch.max.wait.ms = 500
#         src.consumer.fetch.min.bytes = 1
#         src.consumer.interceptor.classes = [io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor]
#         src.consumer.max.partition.fetch.bytes = 1048576
#         src.consumer.max.poll.interval.ms = 300000
#         src.consumer.max.poll.records = 500
#         src.header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.kafka.bootstrap.servers = [broker-europe:9092]
#         src.kafka.client.id = 
#         src.kafka.connections.max.idle.ms = 540000
#         src.kafka.metric.reporters = []
#         src.kafka.metrics.num.samples = 2
#         src.kafka.metrics.sample.window.ms = 30000
#         src.kafka.receive.buffer.bytes = 65536
#         src.kafka.reconnect.backoff.ms = 50
#         src.kafka.request.timeout.ms = 30000
#         src.kafka.retry.backoff.ms = 100
#         src.kafka.sasl.client.callback.handler.class = null
#         src.kafka.sasl.jaas.config = null
#         src.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         src.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         src.kafka.sasl.kerberos.service.name = null
#         src.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         src.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         src.kafka.sasl.login.callback.handler.class = null
#         src.kafka.sasl.login.class = null
#         src.kafka.sasl.login.refresh.buffer.seconds = 300
#         src.kafka.sasl.login.refresh.min.period.seconds = 60
#         src.kafka.sasl.login.refresh.window.factor = 0.8
#         src.kafka.sasl.login.refresh.window.jitter = 0.05
#         src.kafka.sasl.mechanism = GSSAPI
#         src.kafka.security.protocol = PLAINTEXT
#         src.kafka.send.buffer.bytes = 131072
#         src.kafka.ssl.cipher.suites = null
#         src.kafka.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         src.kafka.ssl.endpoint.identification.algorithm = https
#         src.kafka.ssl.engine.factory.class = null
#         src.kafka.ssl.key.password = null
#         src.kafka.ssl.keymanager.algorithm = SunX509
#         src.kafka.ssl.keystore.certificate.chain = null
#         src.kafka.ssl.keystore.key = null
#         src.kafka.ssl.keystore.location = null
#         src.kafka.ssl.keystore.password = null
#         src.kafka.ssl.keystore.type = JKS
#         src.kafka.ssl.protocol = TLSv1.3
#         src.kafka.ssl.provider = null
#         src.kafka.ssl.secure.random.implementation = null
#         src.kafka.ssl.trustmanager.algorithm = PKIX
#         src.kafka.ssl.truststore.certificates = null
#         src.kafka.ssl.truststore.location = null
#         src.kafka.ssl.truststore.password = null
#         src.kafka.ssl.truststore.type = JKS
#         src.key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         task.id = replicate-europe-to-us-0
#         topic.auto.create = true
#         topic.blacklist = []
#         topic.config.sync = false
#         topic.config.sync.interval.ms = 120000
#         topic.create.backoff.ms = 120000
#         topic.poll.interval.ms = 120000
#         topic.preserve.partitions = true
#         topic.regex = null
#         topic.rename.format = ${topic}
#         topic.timestamp.type = CreateTime
#         topic.whitelist = [sales_EUROPE]
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (io.confluent.connect.replicator.ReplicatorSourceTaskConfig:361)
# [2022-01-18 16:03:44,150] INFO [Worker clientId=connect-1, groupId=connect-us] Tasks [replicate-europe-to-us-0] configs updated (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1580)
# [2022-01-18 16:03:44,150] INFO [Worker clientId=connect-1, groupId=connect-us] Handling task config update by restarting tasks [replicate-europe-to-us-0] (org.apache.kafka.connect.runtime.distributed.DistributedHerder:669)
# [2022-01-18 16:03:44,151] INFO [replicate-europe-to-us|task-0] Stopping task replicate-europe-to-us-0 (org.apache.kafka.connect.runtime.Worker:873)
# [2022-01-18 16:03:44,153] INFO [Worker clientId=connect-1, groupId=connect-us] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:225)
# [2022-01-18 16:03:44,153] INFO [Worker clientId=connect-1, groupId=connect-us] (Re-)joining group (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:538)
# [2022-01-18 16:03:44,155] INFO [Worker clientId=connect-1, groupId=connect-us] Successfully joined group with generation Generation{generationId=4, memberId='connect-1-85e0a719-011a-4021-b603-d7d1c6c4d287', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:594)
# [2022-01-18 16:03:44,157] INFO [Worker clientId=connect-1, groupId=connect-us] Successfully synced group in generation Generation{generationId=4, memberId='connect-1-85e0a719-011a-4021-b603-d7d1c6c4d287', protocol='sessioned'} (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:754)
# [2022-01-18 16:03:44,158] INFO [Worker clientId=connect-1, groupId=connect-us] Joined group at generation 4 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-85e0a719-011a-4021-b603-d7d1c6c4d287', leaderUrl='http://connect-us:8083/', offset=6, connectorIds=[replicate-europe-to-us], taskIds=[replicate-europe-to-us-0], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1721)
# [2022-01-18 16:03:44,158] INFO [Worker clientId=connect-1, groupId=connect-us] Starting connectors and tasks using config offset 6 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1247)
# [2022-01-18 16:03:44,164] INFO [Worker clientId=connect-1, groupId=connect-us] Starting task replicate-europe-to-us-0 (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1289)
# [2022-01-18 16:03:44,164] INFO [replicate-europe-to-us|task-0] Creating task replicate-europe-to-us-0 (org.apache.kafka.connect.runtime.Worker:523)
# [2022-01-18 16:03:44,164] INFO [replicate-europe-to-us|task-0] ConnectorConfig values: 
#         config.action.reload = restart
#         connector.class = io.confluent.connect.replicator.ReplicatorSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         name = replicate-europe-to-us
#         predicates = []
#         tasks.max = 1
#         transforms = []
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (org.apache.kafka.connect.runtime.ConnectorConfig:361)
# [2022-01-18 16:03:44,165] INFO [replicate-europe-to-us|task-0] EnrichedConnectorConfig values: 
#         config.action.reload = restart
#         connector.class = io.confluent.connect.replicator.ReplicatorSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         name = replicate-europe-to-us
#         predicates = []
#         tasks.max = 1
#         transforms = []
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig:361)
# [2022-01-18 16:03:44,165] INFO [replicate-europe-to-us|task-0] TaskConfig values: 
#         task.class = class io.confluent.connect.replicator.ReplicatorSourceTask
#  (org.apache.kafka.connect.runtime.TaskConfig:361)
# [2022-01-18 16:03:44,165] INFO [replicate-europe-to-us|task-0] Instantiated task replicate-europe-to-us-0 with version 6.1.1 of type io.confluent.connect.replicator.ReplicatorSourceTask (org.apache.kafka.connect.runtime.Worker:538)
# [2022-01-18 16:03:44,166] INFO [replicate-europe-to-us|task-0] Set up the key converter class io.confluent.connect.replicator.util.ByteArrayConverter for task replicate-europe-to-us-0 using the connector config (org.apache.kafka.connect.runtime.Worker:553)
# [2022-01-18 16:03:44,166] INFO [replicate-europe-to-us|task-0] Set up the value converter class io.confluent.connect.replicator.util.ByteArrayConverter for task replicate-europe-to-us-0 using the connector config (org.apache.kafka.connect.runtime.Worker:559)
# [2022-01-18 16:03:44,166] INFO [replicate-europe-to-us|task-0] Set up the header converter class io.confluent.connect.replicator.util.ByteArrayConverter for task replicate-europe-to-us-0 using the connector config (org.apache.kafka.connect.runtime.Worker:566)
# [2022-01-18 16:03:44,170] INFO [replicate-europe-to-us|task-0] SourceConnectorConfig values: 
#         config.action.reload = restart
#         connector.class = io.confluent.connect.replicator.ReplicatorSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         name = replicate-europe-to-us
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (org.apache.kafka.connect.runtime.SourceConnectorConfig:361)
# [2022-01-18 16:03:44,170] INFO [replicate-europe-to-us|task-0] EnrichedConnectorConfig values: 
#         config.action.reload = restart
#         connector.class = io.confluent.connect.replicator.ReplicatorSourceConnector
#         errors.log.enable = false
#         errors.log.include.messages = false
#         errors.retry.delay.max.ms = 60000
#         errors.retry.timeout = 0
#         errors.tolerance = none
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         name = replicate-europe-to-us
#         predicates = []
#         tasks.max = 1
#         topic.creation.groups = []
#         transforms = []
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (org.apache.kafka.connect.runtime.ConnectorConfig$EnrichedConnectorConfig:361)
# [2022-01-18 16:03:44,170] INFO [replicate-europe-to-us|task-0] Initializing: org.apache.kafka.connect.runtime.TransformationChain{} (org.apache.kafka.connect.runtime.Worker:620)
# [2022-01-18 16:03:44,171] INFO [replicate-europe-to-us|task-0] ProducerConfig values: 
#         acks = -1
#         batch.size = 16384
#         bootstrap.servers = [broker-us:9092]
#         buffer.memory = 33554432
#         client.dns.lookup = use_all_dns_ips
#         client.id = connect-worker-producer-us
#         compression.type = none
#         connections.max.idle.ms = 540000
#         delivery.timeout.ms = 2147483647
#         enable.idempotence = false
#         interceptor.classes = [io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor]
#         internal.auto.downgrade.txn.commit = false
#         key.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#         linger.ms = 0
#         max.block.ms = 9223372036854775807
#         max.in.flight.requests.per.connection = 1
#         max.request.size = 1048576
#         metadata.max.age.ms = 300000
#         metadata.max.idle.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
#         receive.buffer.bytes = 32768
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 2147483647
#         retries = 2147483647
#         retry.backoff.ms = 100
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#         transaction.timeout.ms = 60000
#         transactional.id = null
#         value.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#  (org.apache.kafka.clients.producer.ProducerConfig:361)
# [2022-01-18 16:03:44,184] WARN [replicate-europe-to-us|task-0] The configuration 'metrics.context.resource.connector' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,184] WARN [replicate-europe-to-us|task-0] The configuration 'metrics.context.resource.version' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,184] WARN [replicate-europe-to-us|task-0] The configuration 'metrics.context.connect.group.id' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,184] WARN [replicate-europe-to-us|task-0] The configuration 'metrics.context.resource.type' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,184] WARN [replicate-europe-to-us|task-0] The configuration 'metrics.context.resource.commit.id' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,185] WARN [replicate-europe-to-us|task-0] The configuration 'metrics.context.resource.task' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,185] WARN [replicate-europe-to-us|task-0] The configuration 'metrics.context.connect.kafka.cluster.id' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,185] WARN [replicate-europe-to-us|task-0] The configuration 'confluent.monitoring.interceptor.bootstrap.servers' was supplied but isn't a known config. (org.apache.kafka.clients.producer.ProducerConfig:369)
# [2022-01-18 16:03:44,185] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,185] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,185] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824185 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,188] INFO [Worker clientId=connect-1, groupId=connect-us] Finished starting connectors and tasks (org.apache.kafka.connect.runtime.distributed.DistributedHerder:1275)
# [2022-01-18 16:03:44,189] INFO [replicate-europe-to-us|task-0] [Producer clientId=connect-worker-producer-us] Cluster ID: hgDp9kUsQ-a2gQ40TX01Ew (org.apache.kafka.clients.Metadata:279)
# [2022-01-18 16:03:44,192] INFO [replicate-europe-to-us|task-0] ReplicatorSourceTaskConfig values: 
#         confluent.license = 
#         confluent.topic = _confluent-command
#         dest.kafka.bootstrap.servers = [broker-us:9092]
#         dest.kafka.client.id = 
#         dest.kafka.connections.max.idle.ms = 540000
#         dest.kafka.metric.reporters = []
#         dest.kafka.metrics.num.samples = 2
#         dest.kafka.metrics.sample.window.ms = 30000
#         dest.kafka.receive.buffer.bytes = 65536
#         dest.kafka.reconnect.backoff.ms = 50
#         dest.kafka.request.timeout.ms = 30000
#         dest.kafka.retry.backoff.ms = 100
#         dest.kafka.sasl.client.callback.handler.class = null
#         dest.kafka.sasl.jaas.config = null
#         dest.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         dest.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         dest.kafka.sasl.kerberos.service.name = null
#         dest.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         dest.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         dest.kafka.sasl.login.callback.handler.class = null
#         dest.kafka.sasl.login.class = null
#         dest.kafka.sasl.login.refresh.buffer.seconds = 300
#         dest.kafka.sasl.login.refresh.min.period.seconds = 60
#         dest.kafka.sasl.login.refresh.window.factor = 0.8
#         dest.kafka.sasl.login.refresh.window.jitter = 0.05
#         dest.kafka.sasl.mechanism = GSSAPI
#         dest.kafka.security.protocol = PLAINTEXT
#         dest.kafka.send.buffer.bytes = 131072
#         dest.kafka.ssl.cipher.suites = null
#         dest.kafka.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         dest.kafka.ssl.endpoint.identification.algorithm = https
#         dest.kafka.ssl.engine.factory.class = null
#         dest.kafka.ssl.key.password = null
#         dest.kafka.ssl.keymanager.algorithm = SunX509
#         dest.kafka.ssl.keystore.certificate.chain = null
#         dest.kafka.ssl.keystore.key = null
#         dest.kafka.ssl.keystore.location = null
#         dest.kafka.ssl.keystore.password = null
#         dest.kafka.ssl.keystore.type = JKS
#         dest.kafka.ssl.protocol = TLSv1.3
#         dest.kafka.ssl.provider = null
#         dest.kafka.ssl.secure.random.implementation = null
#         dest.kafka.ssl.trustmanager.algorithm = PKIX
#         dest.kafka.ssl.truststore.certificates = null
#         dest.kafka.ssl.truststore.location = null
#         dest.kafka.ssl.truststore.password = null
#         dest.kafka.ssl.truststore.type = JKS
#         dest.topic.replication.factor = 0
#         dest.zookeeper.connect = 
#         dest.zookeeper.connection.timeout.ms = 6000
#         dest.zookeeper.session.timeout.ms = 6000
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         offset.start = connect
#         offset.timestamps.commit = true
#         offset.topic.commit = true
#         offset.translator.batch.period.ms = 60000
#         offset.translator.batch.size = 1
#         offset.translator.tasks.max = -1
#         offset.translator.tasks.separate = false
#         partition.assignment = AAEAAAACABVfX2NvbnN1bWVyX3RpbWVzdGFtcHMAAAAyAAAAAAAAAAEAAAACAAAAAwAAAAQAAAAFAAAABgAAAAcAAAAIAAAACQAAAAoAAAALAAAADAAAAA0AAAAOAAAADwAAABAAAAARAAAAEgAAABMAAAAUAAAAFQAAABYAAAAXAAAAGAAAABkAAAAaAAAAGwAAABwAAAAdAAAAHgAAAB8AAAAgAAAAIQAAACIAAAAjAAAAJAAAACUAAAAmAAAAJwAAACgAAAApAAAAKgAAACsAAAAsAAAALQAAAC4AAAAvAAAAMAAAADEADHNhbGVzX0VVUk9QRQAAAAEAAAAA/////w==
#         provenance.header.enable = true
#         provenance.header.filter.overrides = 
#         schema.registry.client.basic.auth.credentials.source = URL
#         schema.registry.client.basic.auth.user.info = [hidden]
#         schema.registry.max.schemas.per.subject = 1000
#         schema.registry.topic = null
#         schema.registry.url = null
#         schema.subject.translator.class = null
#         src.consumer.check.crcs = true
#         src.consumer.fetch.max.bytes = 52428800
#         src.consumer.fetch.max.wait.ms = 500
#         src.consumer.fetch.min.bytes = 1
#         src.consumer.interceptor.classes = [io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor]
#         src.consumer.max.partition.fetch.bytes = 1048576
#         src.consumer.max.poll.interval.ms = 300000
#         src.consumer.max.poll.records = 500
#         src.header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.kafka.bootstrap.servers = [broker-europe:9092]
#         src.kafka.client.id = 
#         src.kafka.connections.max.idle.ms = 540000
#         src.kafka.metric.reporters = []
#         src.kafka.metrics.num.samples = 2
#         src.kafka.metrics.sample.window.ms = 30000
#         src.kafka.receive.buffer.bytes = 65536
#         src.kafka.reconnect.backoff.ms = 50
#         src.kafka.request.timeout.ms = 30000
#         src.kafka.retry.backoff.ms = 100
#         src.kafka.sasl.client.callback.handler.class = null
#         src.kafka.sasl.jaas.config = null
#         src.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         src.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         src.kafka.sasl.kerberos.service.name = null
#         src.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         src.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         src.kafka.sasl.login.callback.handler.class = null
#         src.kafka.sasl.login.class = null
#         src.kafka.sasl.login.refresh.buffer.seconds = 300
#         src.kafka.sasl.login.refresh.min.period.seconds = 60
#         src.kafka.sasl.login.refresh.window.factor = 0.8
#         src.kafka.sasl.login.refresh.window.jitter = 0.05
#         src.kafka.sasl.mechanism = GSSAPI
#         src.kafka.security.protocol = PLAINTEXT
#         src.kafka.send.buffer.bytes = 131072
#         src.kafka.ssl.cipher.suites = null
#         src.kafka.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         src.kafka.ssl.endpoint.identification.algorithm = https
#         src.kafka.ssl.engine.factory.class = null
#         src.kafka.ssl.key.password = null
#         src.kafka.ssl.keymanager.algorithm = SunX509
#         src.kafka.ssl.keystore.certificate.chain = null
#         src.kafka.ssl.keystore.key = null
#         src.kafka.ssl.keystore.location = null
#         src.kafka.ssl.keystore.password = null
#         src.kafka.ssl.keystore.type = JKS
#         src.kafka.ssl.protocol = TLSv1.3
#         src.kafka.ssl.provider = null
#         src.kafka.ssl.secure.random.implementation = null
#         src.kafka.ssl.trustmanager.algorithm = PKIX
#         src.kafka.ssl.truststore.certificates = null
#         src.kafka.ssl.truststore.location = null
#         src.kafka.ssl.truststore.password = null
#         src.kafka.ssl.truststore.type = JKS
#         src.key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         task.id = replicate-europe-to-us-0
#         topic.auto.create = true
#         topic.blacklist = []
#         topic.config.sync = false
#         topic.config.sync.interval.ms = 120000
#         topic.create.backoff.ms = 120000
#         topic.poll.interval.ms = 120000
#         topic.preserve.partitions = true
#         topic.regex = null
#         topic.rename.format = ${topic}
#         topic.timestamp.type = CreateTime
#         topic.whitelist = [sales_EUROPE]
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (io.confluent.connect.replicator.ReplicatorSourceTaskConfig:361)
# [2022-01-18 16:03:44,192] INFO [replicate-europe-to-us|task-0] Starting Replicator source task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:274)
# [2022-01-18 16:03:44,196] INFO [replicate-europe-to-us|task-0] AdminClientConfig values: 
#         bootstrap.servers = [broker-us:9092]
#         client.dns.lookup = use_all_dns_ips
#         client.id = 
#         connections.max.idle.ms = 300000
#         default.api.timeout.ms = 60000
#         metadata.max.age.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         receive.buffer.bytes = 65536
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retries = 2147483647
#         retry.backoff.ms = 100
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#  (org.apache.kafka.clients.admin.AdminClientConfig:361)
# [2022-01-18 16:03:44,198] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,198] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,198] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824198 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,201] INFO [replicate-europe-to-us|task-0] AdminClientConfig values: 
#         bootstrap.servers = [broker-europe:9092]
#         client.dns.lookup = use_all_dns_ips
#         client.id = 
#         connections.max.idle.ms = 300000
#         default.api.timeout.ms = 60000
#         metadata.max.age.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         receive.buffer.bytes = 65536
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retries = 2147483647
#         retry.backoff.ms = 100
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#  (org.apache.kafka.clients.admin.AdminClientConfig:361)
# [2022-01-18 16:03:44,204] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,204] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,204] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824204 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,223] INFO [replicate-europe-to-us|task-0] Source cluster ID: XesYUUWaRr2NKrPXROZFvQ (io.confluent.connect.replicator.ReplicatorSourceTask:388)
# [2022-01-18 16:03:44,223] INFO [replicate-europe-to-us|task-0] Destination cluster ID: hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.connect.replicator.ReplicatorSourceTask:389)
# [2022-01-18 16:03:44,223] INFO [replicate-europe-to-us|task-0] ConsumerConfig values: 
#         allow.auto.create.topics = false
#         auto.commit.interval.ms = 5000
#         auto.offset.reset = none
#         bootstrap.servers = [broker-europe:9092]
#         check.crcs = true
#         client.dns.lookup = use_all_dns_ips
#         client.id = replicate-europe-to-us-0
#         client.rack = 
#         connections.max.idle.ms = 540000
#         default.api.timeout.ms = 60000
#         enable.auto.commit = false
#         exclude.internal.topics = true
#         fetch.max.bytes = 52428800
#         fetch.max.wait.ms = 500
#         fetch.min.bytes = 1
#         group.id = replicate-europe-to-us
#         group.instance.id = null
#         heartbeat.interval.ms = 3000
#         interceptor.classes = [io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor]
#         internal.leave.group.on.close = true
#         internal.throw.on.fetch.stable.offset.unsupported = false
#         isolation.level = read_uncommitted
#         key.deserializer = class org.apache.kafka.common.serialization.ByteArrayDeserializer
#         max.partition.fetch.bytes = 1048576
#         max.poll.interval.ms = 300000
#         max.poll.records = 500
#         metadata.max.age.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         partition.assignment.strategy = [class org.apache.kafka.clients.consumer.RangeAssignor]
#         receive.buffer.bytes = 65536
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retry.backoff.ms = 100
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         session.timeout.ms = 10000
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#         value.deserializer = class org.apache.kafka.common.serialization.ByteArrayDeserializer
#  (org.apache.kafka.clients.consumer.ConsumerConfig:361)
# [2022-01-18 16:03:44,225] WARN [replicate-europe-to-us|task-0] The configuration 'confluent.monitoring.interceptor.bootstrap.servers' was supplied but isn't a known config. (org.apache.kafka.clients.consumer.ConsumerConfig:369)
# [2022-01-18 16:03:44,226] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,226] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,226] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824226 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,226] INFO [replicate-europe-to-us|task-0] ConsumerOffsetsTranslatorConfig values: 
#         confluent.license = 
#         confluent.topic = _confluent-command
#         dest.kafka.bootstrap.servers = [broker-us:9092]
#         dest.kafka.client.id = 
#         dest.kafka.connections.max.idle.ms = 540000
#         dest.kafka.metric.reporters = []
#         dest.kafka.metrics.num.samples = 2
#         dest.kafka.metrics.sample.window.ms = 30000
#         dest.kafka.receive.buffer.bytes = 65536
#         dest.kafka.reconnect.backoff.ms = 50
#         dest.kafka.request.timeout.ms = 30000
#         dest.kafka.retry.backoff.ms = 100
#         dest.kafka.sasl.client.callback.handler.class = null
#         dest.kafka.sasl.jaas.config = null
#         dest.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         dest.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         dest.kafka.sasl.kerberos.service.name = null
#         dest.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         dest.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         dest.kafka.sasl.login.callback.handler.class = null
#         dest.kafka.sasl.login.class = null
#         dest.kafka.sasl.login.refresh.buffer.seconds = 300
#         dest.kafka.sasl.login.refresh.min.period.seconds = 60
#         dest.kafka.sasl.login.refresh.window.factor = 0.8
#         dest.kafka.sasl.login.refresh.window.jitter = 0.05
#         dest.kafka.sasl.mechanism = GSSAPI
#         dest.kafka.security.protocol = PLAINTEXT
#         dest.kafka.send.buffer.bytes = 131072
#         dest.kafka.ssl.cipher.suites = null
#         dest.kafka.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         dest.kafka.ssl.endpoint.identification.algorithm = https
#         dest.kafka.ssl.engine.factory.class = null
#         dest.kafka.ssl.key.password = null
#         dest.kafka.ssl.keymanager.algorithm = SunX509
#         dest.kafka.ssl.keystore.certificate.chain = null
#         dest.kafka.ssl.keystore.key = null
#         dest.kafka.ssl.keystore.location = null
#         dest.kafka.ssl.keystore.password = null
#         dest.kafka.ssl.keystore.type = JKS
#         dest.kafka.ssl.protocol = TLSv1.3
#         dest.kafka.ssl.provider = null
#         dest.kafka.ssl.secure.random.implementation = null
#         dest.kafka.ssl.trustmanager.algorithm = PKIX
#         dest.kafka.ssl.truststore.certificates = null
#         dest.kafka.ssl.truststore.location = null
#         dest.kafka.ssl.truststore.password = null
#         dest.kafka.ssl.truststore.type = JKS
#         dest.topic.replication.factor = 0
#         dest.zookeeper.connect = 
#         dest.zookeeper.connection.timeout.ms = 6000
#         dest.zookeeper.session.timeout.ms = 6000
#         fetch.offset.expiry.ms = 600000
#         fetch.offset.retry.backoff.ms = 100
#         header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         offset.start = connect
#         offset.timestamps.commit = true
#         offset.topic.commit = true
#         offset.translator.batch.period.ms = 60000
#         offset.translator.batch.size = 1
#         offset.translator.tasks.max = -1
#         offset.translator.tasks.separate = false
#         provenance.header.enable = true
#         provenance.header.filter.overrides = 
#         schema.registry.client.basic.auth.credentials.source = URL
#         schema.registry.client.basic.auth.user.info = [hidden]
#         schema.registry.max.schemas.per.subject = 1000
#         schema.registry.topic = null
#         schema.registry.url = null
#         schema.subject.translator.class = null
#         src.consumer.check.crcs = true
#         src.consumer.fetch.max.bytes = 52428800
#         src.consumer.fetch.max.wait.ms = 500
#         src.consumer.fetch.min.bytes = 1
#         src.consumer.interceptor.classes = [io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor]
#         src.consumer.max.partition.fetch.bytes = 1048576
#         src.consumer.max.poll.interval.ms = 300000
#         src.consumer.max.poll.records = 500
#         src.header.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.kafka.bootstrap.servers = [broker-europe:9092]
#         src.kafka.client.id = 
#         src.kafka.connections.max.idle.ms = 540000
#         src.kafka.metric.reporters = []
#         src.kafka.metrics.num.samples = 2
#         src.kafka.metrics.sample.window.ms = 30000
#         src.kafka.receive.buffer.bytes = 65536
#         src.kafka.reconnect.backoff.ms = 50
#         src.kafka.request.timeout.ms = 30000
#         src.kafka.retry.backoff.ms = 100
#         src.kafka.sasl.client.callback.handler.class = null
#         src.kafka.sasl.jaas.config = null
#         src.kafka.sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         src.kafka.sasl.kerberos.min.time.before.relogin = 60000
#         src.kafka.sasl.kerberos.service.name = null
#         src.kafka.sasl.kerberos.ticket.renew.jitter = 0.05
#         src.kafka.sasl.kerberos.ticket.renew.window.factor = 0.8
#         src.kafka.sasl.login.callback.handler.class = null
#         src.kafka.sasl.login.class = null
#         src.kafka.sasl.login.refresh.buffer.seconds = 300
#         src.kafka.sasl.login.refresh.min.period.seconds = 60
#         src.kafka.sasl.login.refresh.window.factor = 0.8
#         src.kafka.sasl.login.refresh.window.jitter = 0.05
#         src.kafka.sasl.mechanism = GSSAPI
#         src.kafka.security.protocol = PLAINTEXT
#         src.kafka.send.buffer.bytes = 131072
#         src.kafka.ssl.cipher.suites = null
#         src.kafka.ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         src.kafka.ssl.endpoint.identification.algorithm = https
#         src.kafka.ssl.engine.factory.class = null
#         src.kafka.ssl.key.password = null
#         src.kafka.ssl.keymanager.algorithm = SunX509
#         src.kafka.ssl.keystore.certificate.chain = null
#         src.kafka.ssl.keystore.key = null
#         src.kafka.ssl.keystore.location = null
#         src.kafka.ssl.keystore.password = null
#         src.kafka.ssl.keystore.type = JKS
#         src.kafka.ssl.protocol = TLSv1.3
#         src.kafka.ssl.provider = null
#         src.kafka.ssl.secure.random.implementation = null
#         src.kafka.ssl.trustmanager.algorithm = PKIX
#         src.kafka.ssl.truststore.certificates = null
#         src.kafka.ssl.truststore.location = null
#         src.kafka.ssl.truststore.password = null
#         src.kafka.ssl.truststore.type = JKS
#         src.key.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         src.value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#         topic.auto.create = true
#         topic.blacklist = []
#         topic.config.sync = false
#         topic.config.sync.interval.ms = 120000
#         topic.create.backoff.ms = 120000
#         topic.poll.interval.ms = 120000
#         topic.preserve.partitions = true
#         topic.regex = null
#         topic.rename.format = ${topic}
#         topic.timestamp.type = CreateTime
#         topic.whitelist = [sales_EUROPE]
#         value.converter = class io.confluent.connect.replicator.util.ByteArrayConverter
#  (io.confluent.connect.replicator.offsets.ConsumerOffsetsTranslatorConfig:361)
# [2022-01-18 16:03:44,227] INFO [replicate-europe-to-us|task-0] Requesting metadata refresh after 1 new topics were added (io.confluent.connect.replicator.util.ReplicatorAdminClient:251)
# [2022-01-18 16:03:44,227] INFO [replicate-europe-to-us|task-0] ConsumerTimestampsWriterConfig values: 
#         timestamps.producer.max.per.partition = 2147483647
#         timestamps.producer.topic.blacklist = []
#         timestamps.producer.topic.regex = null
#         timestamps.producer.topic.whitelist = null
#         timestamps.topic.num.partitions = 50
#         timestamps.topic.replication.factor = 3
#  (io.confluent.connect.replicator.offsets.ConsumerTimestampsWriterConfig:361)
# [2022-01-18 16:03:44,240] INFO [replicate-europe-to-us|task-0] ProducerConfig values: 
#         acks = -1
#         batch.size = 16384
#         bootstrap.servers = [broker-europe:9092]
#         buffer.memory = 33554432
#         client.dns.lookup = use_all_dns_ips
#         client.id = producer-6
#         compression.type = lz4
#         connections.max.idle.ms = 540000
#         delivery.timeout.ms = 2147483647
#         enable.idempotence = false
#         interceptor.classes = []
#         internal.auto.downgrade.txn.commit = false
#         key.serializer = class io.confluent.connect.replicator.offsets.GroupTopicPartitionSerializer
#         linger.ms = 500
#         max.block.ms = 60000
#         max.in.flight.requests.per.connection = 1
#         max.request.size = 10485760
#         metadata.max.age.ms = 300000
#         metadata.max.idle.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
#         receive.buffer.bytes = 32768
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retries = 2147483647
#         retry.backoff.ms = 500
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#         transaction.timeout.ms = 60000
#         transactional.id = null
#         value.serializer = class io.confluent.connect.replicator.offsets.TimestampAndDeltaSerializer
#  (org.apache.kafka.clients.producer.ProducerConfig:361)
# [2022-01-18 16:03:44,244] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,245] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,245] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824244 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,246] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Subscribed to partition(s): __consumer_timestamps-0, __consumer_timestamps-1, __consumer_timestamps-2, __consumer_timestamps-3, __consumer_timestamps-4, __consumer_timestamps-5, __consumer_timestamps-6, __consumer_timestamps-7, __consumer_timestamps-8, __consumer_timestamps-9, __consumer_timestamps-10, __consumer_timestamps-11, __consumer_timestamps-12, __consumer_timestamps-13, __consumer_timestamps-14, __consumer_timestamps-15, __consumer_timestamps-16, __consumer_timestamps-17, __consumer_timestamps-18, __consumer_timestamps-19, __consumer_timestamps-20, __consumer_timestamps-21, __consumer_timestamps-22, __consumer_timestamps-23, __consumer_timestamps-24, __consumer_timestamps-25, __consumer_timestamps-26, __consumer_timestamps-27, __consumer_timestamps-28, __consumer_timestamps-29, __consumer_timestamps-30, __consumer_timestamps-31, __consumer_timestamps-32, __consumer_timestamps-33, __consumer_timestamps-34, __consumer_timestamps-35, __consumer_timestamps-36, __consumer_timestamps-37, __consumer_timestamps-38, __consumer_timestamps-39, __consumer_timestamps-40, __consumer_timestamps-41, __consumer_timestamps-42, __consumer_timestamps-43, __consumer_timestamps-44, __consumer_timestamps-45, __consumer_timestamps-46, __consumer_timestamps-47, __consumer_timestamps-48, __consumer_timestamps-49, sales_EUROPE-0 (org.apache.kafka.clients.consumer.KafkaConsumer:1116)
# [2022-01-18 16:03:44,249] INFO [replicate-europe-to-us|task-0] Requesting metadata refresh after 1 new topics were added (io.confluent.connect.replicator.util.ReplicatorAdminClient:251)
# [2022-01-18 16:03:44,251] INFO [replicate-europe-to-us|task-0] [Producer clientId=producer-6] Cluster ID: XesYUUWaRr2NKrPXROZFvQ (org.apache.kafka.clients.Metadata:279)
# [2022-01-18 16:03:44,264] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Cluster ID: XesYUUWaRr2NKrPXROZFvQ (org.apache.kafka.clients.Metadata:279)
# [2022-01-18 16:03:44,265] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Discovered group coordinator broker-europe:9092 (id: 2147483646 rack: null) (org.apache.kafka.clients.consumer.internals.AbstractCoordinator:844)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-15 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-44 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-11 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-40 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-23 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-19 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-48 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-31 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-27 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-39 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-6 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-35 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-2 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-47 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-14 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-43 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-10 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,268] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-22 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-18 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-30 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-26 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-38 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-5 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-34 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-1 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-46 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-13 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-42 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-9 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-21 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,269] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-17 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-29 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-25 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-37 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-4 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-33 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-45 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-12 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-41 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-8 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-20 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition sales_EUROPE-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-49 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,270] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-16 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-28 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-24 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-7 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-36 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-3 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Found no committed offset for partition __consumer_timestamps-32 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1354)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-15 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-44 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-11 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-40 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-23 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-19 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-48 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,271] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-31 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-27 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-39 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-6 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-35 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-2 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-47 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-14 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-43 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-10 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-22 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-18 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-30 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-26 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-38 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-5 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-34 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-1 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-46 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,272] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-13 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-42 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-9 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-21 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-17 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-29 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-25 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-37 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-4 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-33 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-0 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-45 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-12 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-41 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-8 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,273] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-20 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition sales_EUROPE-0 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-49 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-16 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-28 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-24 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-7 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-36 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-3 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Seeking to EARLIEST offset of partition __consumer_timestamps-32 (org.apache.kafka.clients.consumer.internals.SubscriptionState:618)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] Started kafka replicator task replicate-europe-to-us-0 replicating topic partitions [__consumer_timestamps-0, __consumer_timestamps-1, __consumer_timestamps-2, __consumer_timestamps-3, __consumer_timestamps-4, __consumer_timestamps-5, __consumer_timestamps-6, __consumer_timestamps-7, __consumer_timestamps-8, __consumer_timestamps-9, __consumer_timestamps-10, __consumer_timestamps-11, __consumer_timestamps-12, __consumer_timestamps-13, __consumer_timestamps-14, __consumer_timestamps-15, __consumer_timestamps-16, __consumer_timestamps-17, __consumer_timestamps-18, __consumer_timestamps-19, __consumer_timestamps-20, __consumer_timestamps-21, __consumer_timestamps-22, __consumer_timestamps-23, __consumer_timestamps-24, __consumer_timestamps-25, __consumer_timestamps-26, __consumer_timestamps-27, __consumer_timestamps-28, __consumer_timestamps-29, __consumer_timestamps-30, __consumer_timestamps-31, __consumer_timestamps-32, __consumer_timestamps-33, __consumer_timestamps-34, __consumer_timestamps-35, __consumer_timestamps-36, __consumer_timestamps-37, __consumer_timestamps-38, __consumer_timestamps-39, __consumer_timestamps-40, __consumer_timestamps-41, __consumer_timestamps-42, __consumer_timestamps-43, __consumer_timestamps-44, __consumer_timestamps-45, __consumer_timestamps-46, __consumer_timestamps-47, __consumer_timestamps-48, __consumer_timestamps-49, sales_EUROPE-0] (io.confluent.connect.replicator.ReplicatorSourceTask:342)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] Setting up metrics recording for task replicate-europe-to-us-0... (io.confluent.connect.replicator.ReplicatorSourceTask:347)
# [2022-01-18 16:03:44,274] INFO [replicate-europe-to-us|task-0] Registering Confluent Replicator metrics with JMX for task 'replicate-europe-to-us-0' (io.confluent.connect.replicator.metrics.ConfluentReplicatorMetrics:60)
# [2022-01-18 16:03:44,275] INFO [replicate-europe-to-us|task-0] Successfully registered Confluent Replicator metrics with JMX for task 'replicate-europe-to-us-0' (io.confluent.connect.replicator.metrics.ConfluentReplicatorMetrics:69)
# [2022-01-18 16:03:44,284] INFO [replicate-europe-to-us|task-0] ConsumerConfig values: 
#         allow.auto.create.topics = true
#         auto.commit.interval.ms = 5000
#         auto.offset.reset = none
#         bootstrap.servers = [broker-europe:9092]
#         check.crcs = true
#         client.dns.lookup = use_all_dns_ips
#         client.id = confluent-replicator-end-offsets-consumer-client
#         client.rack = 
#         connections.max.idle.ms = 540000
#         default.api.timeout.ms = 60000
#         enable.auto.commit = false
#         exclude.internal.topics = true
#         fetch.max.bytes = 52428800
#         fetch.max.wait.ms = 500
#         fetch.min.bytes = 1
#         group.id = confluent-replicator-end-offsets-consumer-group
#         group.instance.id = null
#         heartbeat.interval.ms = 3000
#         interceptor.classes = [io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor]
#         internal.leave.group.on.close = true
#         internal.throw.on.fetch.stable.offset.unsupported = false
#         isolation.level = read_uncommitted
#         key.deserializer = class org.apache.kafka.common.serialization.ByteArrayDeserializer
#         max.partition.fetch.bytes = 1048576
#         max.poll.interval.ms = 300000
#         max.poll.records = 500
#         metadata.max.age.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         partition.assignment.strategy = [class org.apache.kafka.clients.consumer.RangeAssignor]
#         receive.buffer.bytes = 65536
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retry.backoff.ms = 100
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         session.timeout.ms = 10000
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#         value.deserializer = class org.apache.kafka.common.serialization.ByteArrayDeserializer
#  (org.apache.kafka.clients.consumer.ConsumerConfig:361)
# [2022-01-18 16:03:44,286] WARN [replicate-europe-to-us|task-0] The configuration 'confluent.monitoring.interceptor.bootstrap.servers' was supplied but isn't a known config. (org.apache.kafka.clients.consumer.ConsumerConfig:369)
# [2022-01-18 16:03:44,286] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,286] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,286] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824286 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,287] INFO [replicate-europe-to-us|task-0] Successfully set up metrics recording for task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:354)
# [2022-01-18 16:03:44,287] INFO [replicate-europe-to-us|task-0] Successfully started up Replicator source task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:355)
# [2022-01-18 16:03:44,287] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Source task finished initialization and start (org.apache.kafka.connect.runtime.WorkerSourceTask:233)
# [2022-01-18 16:03:44,293] INFO [replicate-europe-to-us|task-0] [Consumer clientId=confluent-replicator-end-offsets-consumer-client, groupId=confluent-replicator-end-offsets-consumer-group] Cluster ID: XesYUUWaRr2NKrPXROZFvQ (org.apache.kafka.clients.Metadata:279)
# [2022-01-18 16:03:44,296] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-15 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,296] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-44 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,296] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-11 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,297] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-40 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,297] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-23 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,297] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-19 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,297] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-48 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,297] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-31 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,297] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-27 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,297] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-39 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,298] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-6 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,298] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-35 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,298] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-2 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,298] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-47 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,298] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-14 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-43 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-10 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-22 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-18 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-30 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-26 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-38 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,299] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-5 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-34 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-1 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-46 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-13 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-42 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-9 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-21 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,300] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-17 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,301] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-29 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,301] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-25 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,301] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-37 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,301] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-4 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-33 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-0 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-45 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-12 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-41 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-8 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-20 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,302] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition sales_EUROPE-0 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-49 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-16 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-28 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-24 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-7 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-36 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-3 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,303] INFO [replicate-europe-to-us|task-0] [Consumer clientId=replicate-europe-to-us-0, groupId=replicate-europe-to-us] Resetting offset for partition __consumer_timestamps-32 to position FetchPosition{offset=0, offsetEpoch=Optional.empty, currentLeader=LeaderAndEpoch{leader=Optional[broker-europe:9092 (id: 1 rack: null)], epoch=0}}. (org.apache.kafka.clients.consumer.internals.SubscriptionState:396)
# [2022-01-18 16:03:44,313] INFO [replicate-europe-to-us|task-0] creating interceptor (io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor:69)
# [2022-01-18 16:03:44,314] INFO [replicate-europe-to-us|task-0] MonitoringInterceptorConfig values: 
#         confluent.monitoring.interceptor.publishMs = 15000
#         confluent.monitoring.interceptor.topic = _confluent-monitoring
#  (io.confluent.monitoring.clients.interceptor.MonitoringInterceptorConfig:361)
# [2022-01-18 16:03:44,314] INFO [replicate-europe-to-us|task-0] ProducerConfig values: 
#         acks = -1
#         batch.size = 16384
#         bootstrap.servers = [broker-metrics:9092]
#         buffer.memory = 33554432
#         client.dns.lookup = use_all_dns_ips
#         client.id = confluent.monitoring.interceptor.replicate-europe-to-us-0
#         compression.type = lz4
#         connections.max.idle.ms = 540000
#         delivery.timeout.ms = 120000
#         enable.idempotence = false
#         interceptor.classes = []
#         internal.auto.downgrade.txn.commit = false
#         key.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#         linger.ms = 500
#         max.block.ms = 60000
#         max.in.flight.requests.per.connection = 1
#         max.request.size = 10485760
#         metadata.max.age.ms = 300000
#         metadata.max.idle.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
#         receive.buffer.bytes = 32768
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retries = 2147483647
#         retry.backoff.ms = 500
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#         transaction.timeout.ms = 60000
#         transactional.id = null
#         value.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#  (org.apache.kafka.clients.producer.ProducerConfig:361)
# [2022-01-18 16:03:44,318] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,318] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,318] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824318 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,319] INFO [replicate-europe-to-us|task-0] interceptor=confluent.monitoring.interceptor.replicate-europe-to-us-0 created for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=XesYUUWaRr2NKrPXROZFvQ group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:153)
# [2022-01-18 16:03:44,325] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.replicate-europe-to-us-0] Cluster ID: a3gnKK_IT4u0dIYZwCa-aQ (org.apache.kafka.clients.Metadata:279)
# [2022-01-18 16:03:44,328] INFO [replicate-europe-to-us|task-0] creating interceptor (io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor:74)
# [2022-01-18 16:03:44,329] INFO [replicate-europe-to-us|task-0] MonitoringInterceptorConfig values: 
#         confluent.monitoring.interceptor.publishMs = 15000
#         confluent.monitoring.interceptor.topic = _confluent-monitoring
#  (io.confluent.monitoring.clients.interceptor.MonitoringInterceptorConfig:361)
# [2022-01-18 16:03:44,329] INFO [replicate-europe-to-us|task-0] ProducerConfig values: 
#         acks = -1
#         batch.size = 16384
#         bootstrap.servers = [broker-metrics:9092]
#         buffer.memory = 33554432
#         client.dns.lookup = use_all_dns_ips
#         client.id = confluent.monitoring.interceptor.connect-worker-producer-us
#         compression.type = lz4
#         connections.max.idle.ms = 540000
#         delivery.timeout.ms = 120000
#         enable.idempotence = false
#         interceptor.classes = []
#         internal.auto.downgrade.txn.commit = false
#         key.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#         linger.ms = 500
#         max.block.ms = 60000
#         max.in.flight.requests.per.connection = 1
#         max.request.size = 10485760
#         metadata.max.age.ms = 300000
#         metadata.max.idle.ms = 300000
#         metric.reporters = []
#         metrics.num.samples = 2
#         metrics.recording.level = INFO
#         metrics.sample.window.ms = 30000
#         partitioner.class = class org.apache.kafka.clients.producer.internals.DefaultPartitioner
#         receive.buffer.bytes = 32768
#         reconnect.backoff.max.ms = 1000
#         reconnect.backoff.ms = 50
#         request.timeout.ms = 30000
#         retries = 2147483647
#         retry.backoff.ms = 500
#         sasl.client.callback.handler.class = null
#         sasl.jaas.config = null
#         sasl.kerberos.kinit.cmd = /usr/bin/kinit
#         sasl.kerberos.min.time.before.relogin = 60000
#         sasl.kerberos.service.name = null
#         sasl.kerberos.ticket.renew.jitter = 0.05
#         sasl.kerberos.ticket.renew.window.factor = 0.8
#         sasl.login.callback.handler.class = null
#         sasl.login.class = null
#         sasl.login.refresh.buffer.seconds = 300
#         sasl.login.refresh.min.period.seconds = 60
#         sasl.login.refresh.window.factor = 0.8
#         sasl.login.refresh.window.jitter = 0.05
#         sasl.mechanism = GSSAPI
#         security.protocol = PLAINTEXT
#         security.providers = null
#         send.buffer.bytes = 131072
#         socket.connection.setup.timeout.max.ms = 127000
#         socket.connection.setup.timeout.ms = 10000
#         ssl.cipher.suites = null
#         ssl.enabled.protocols = [TLSv1.2, TLSv1.3]
#         ssl.endpoint.identification.algorithm = https
#         ssl.engine.factory.class = null
#         ssl.key.password = null
#         ssl.keymanager.algorithm = SunX509
#         ssl.keystore.certificate.chain = null
#         ssl.keystore.key = null
#         ssl.keystore.location = null
#         ssl.keystore.password = null
#         ssl.keystore.type = JKS
#         ssl.protocol = TLSv1.3
#         ssl.provider = null
#         ssl.secure.random.implementation = null
#         ssl.trustmanager.algorithm = PKIX
#         ssl.truststore.certificates = null
#         ssl.truststore.location = null
#         ssl.truststore.password = null
#         ssl.truststore.type = JKS
#         transaction.timeout.ms = 60000
#         transactional.id = null
#         value.serializer = class org.apache.kafka.common.serialization.ByteArraySerializer
#  (org.apache.kafka.clients.producer.ProducerConfig:361)
# [2022-01-18 16:03:44,333] INFO [replicate-europe-to-us|task-0] Kafka version: 6.1.1-ce (org.apache.kafka.common.utils.AppInfoParser:119)
# [2022-01-18 16:03:44,334] INFO [replicate-europe-to-us|task-0] Kafka commitId: 73deb3aeb1f8647c (org.apache.kafka.common.utils.AppInfoParser:120)
# [2022-01-18 16:03:44,334] INFO [replicate-europe-to-us|task-0] Kafka startTimeMs: 1642521824333 (org.apache.kafka.common.utils.AppInfoParser:121)
# [2022-01-18 16:03:44,334] INFO [replicate-europe-to-us|task-0] interceptor=confluent.monitoring.interceptor.connect-worker-producer-us created for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:153)
# [2022-01-18 16:03:44,334] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:372)
# org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-01-18 16:03:44,337] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:372)
# org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-01-18 16:03:44,337] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} failed to send record to sales_EUROPE:  (org.apache.kafka.connect.runtime.WorkerSourceTask:372)
# org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-01-18 16:03:44,337] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer-us] Cluster ID: a3gnKK_IT4u0dIYZwCa-aQ (org.apache.kafka.clients.Metadata:279)
# [2022-01-18 16:04:14,259] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:04:14,259] INFO [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:04:19,259] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:04:19,259] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:191)
# org.apache.kafka.connect.errors.ConnectException: Unrecoverable exception from producer send callback
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.maybeThrowProducerSendException(WorkerSourceTask.java:284)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:243)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.common.InvalidRecordException: One or more records have been rejected
# [2022-01-18 16:04:19,260] INFO [replicate-europe-to-us|task-0] Closing kafka replicator task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:1195)
# [2022-01-18 16:04:19,260] INFO [replicate-europe-to-us|task-0] App info kafka.admin.client for adminclient-15 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:19,261] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,261] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,261] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,264] INFO [replicate-europe-to-us|task-0] App info kafka.admin.client for adminclient-14 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:19,264] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,264] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,265] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,266] INFO [replicate-europe-to-us|task-0] Publish thread interrupted for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=XesYUUWaRr2NKrPXROZFvQ group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-01-18 16:04:19,266] INFO [replicate-europe-to-us|task-0] Publishing Monitoring Metrics stopped for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=XesYUUWaRr2NKrPXROZFvQ group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-01-18 16:04:19,266] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.replicate-europe-to-us-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:04:19,269] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,269] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,269] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,269] INFO [replicate-europe-to-us|task-0] App info kafka.producer for confluent.monitoring.interceptor.replicate-europe-to-us-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:19,269] INFO [replicate-europe-to-us|task-0] Closed monitoring interceptor for client_id=replicate-europe-to-us-0 client_type=CONSUMER session= cluster=XesYUUWaRr2NKrPXROZFvQ group=replicate-europe-to-us (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-01-18 16:04:19,270] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,270] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,270] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,271] INFO [replicate-europe-to-us|task-0] App info kafka.consumer for replicate-europe-to-us-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:19,271] INFO [replicate-europe-to-us|task-0] [Producer clientId=producer-6] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:04:19,272] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,272] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,272] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,272] INFO [replicate-europe-to-us|task-0] App info kafka.producer for producer-6 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:19,272] INFO [replicate-europe-to-us|task-0] Shutting down metrics recording for task replicate-europe-to-us-0 (io.confluent.connect.replicator.ReplicatorSourceTask:1217)
# [2022-01-18 16:04:19,282] INFO [replicate-europe-to-us|task-0] Unregistering Confluent Replicator metrics with JMX for task 'replicate-europe-to-us-0' (io.confluent.connect.replicator.metrics.ConfluentReplicatorMetrics:86)
# [2022-01-18 16:04:19,283] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,283] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,283] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,283] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,284] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,284] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,285] INFO [replicate-europe-to-us|task-0] App info kafka.consumer for confluent-replicator-end-offsets-consumer-client unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:19,286] INFO [replicate-europe-to-us|task-0] [Producer clientId=connect-worker-producer-us] Closing the Kafka producer with timeoutMillis = 30000 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:04:19,288] INFO [replicate-europe-to-us|task-0] Publish thread interrupted for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-01-18 16:04:19,288] INFO [replicate-europe-to-us|task-0] Publishing Monitoring Metrics stopped for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-01-18 16:04:19,288] INFO [replicate-europe-to-us|task-0] [Producer clientId=confluent.monitoring.interceptor.connect-worker-producer-us] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
# [2022-01-18 16:04:19,289] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] App info kafka.producer for confluent.monitoring.interceptor.connect-worker-producer-us unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] Closed monitoring interceptor for client_id=connect-worker-producer-us client_type=PRODUCER session= cluster=hgDp9kUsQ-a2gQ40TX01Ew (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:668)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:672)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:678)
# [2022-01-18 16:04:19,290] INFO [replicate-europe-to-us|task-0] App info kafka.producer for connect-worker-producer-us unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-01-18 16:04:44,188] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:04:44,189] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:04:49,189] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:04:49,189] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:05:44,135] INFO [replicate-europe-to-us|worker] Found matching topics: [__consumer_timestamps, sales_EUROPE] (io.confluent.connect.replicator.NewTopicMonitorThread:329)
# [2022-01-18 16:05:49,190] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:05:49,190] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:05:54,190] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:05:54,190] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:06:54,191] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:06:54,191] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:06:59,191] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:06:59,191] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:07:44,138] INFO [replicate-europe-to-us|worker] Found matching topics: [__consumer_timestamps, sales_EUROPE] (io.confluent.connect.replicator.NewTopicMonitorThread:329)
# [2022-01-18 16:07:59,192] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:07:59,192] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:08:04,192] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:08:04,192] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:09:04,192] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:09:04,193] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:09:09,193] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:09:09,193] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:09:44,141] INFO [replicate-europe-to-us|worker] Found matching topics: [__consumer_timestamps, sales_EUROPE] (io.confluent.connect.replicator.NewTopicMonitorThread:329)
# [2022-01-18 16:10:09,193] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:10:09,194] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:10:14,194] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:10:14,194] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:11:14,194] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:11:14,194] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:11:19,194] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:11:19,194] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)
# [2022-01-18 16:11:44,144] INFO [replicate-europe-to-us|worker] Found matching topics: [__consumer_timestamps, sales_EUROPE] (io.confluent.connect.replicator.NewTopicMonitorThread:329)
# [2022-01-18 16:12:19,194] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-18 16:12:19,194] INFO [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} flushing 3 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-18 16:12:24,195] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to flush, timed out while waiting for producer to flush outstanding 3 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-18 16:12:24,195] ERROR [replicate-europe-to-us|task-0|offsets] WorkerSourceTask{id=replicate-europe-to-us-0} Failed to commit offsets (org.apache.kafka.connect.runtime.SourceTaskOffsetCommitter:116)



# # docker container exec -i control-center bash -c "control-center-console-consumer /etc/confluent-control-center/control-center.properties --topic --from-beginning _confluent-monitoring"

