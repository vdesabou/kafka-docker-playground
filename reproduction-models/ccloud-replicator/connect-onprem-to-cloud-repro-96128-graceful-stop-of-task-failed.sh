#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-connect-onprem-to-cloud.repro-96128-graceful-stop-of-task-failed.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
delete_topic products
sleep 3
create_topic products
set -e

log "Sending messages to topic products on source OnPREM cluster"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic products

log "Create connector with small batch.size"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-onprem-to-cloud",
          "src.kafka.bootstrap.servers": "broker:9092",
          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "products",
          "topic.config.sync": false,
          "topic.auto.create": false,

          "producer.override.batch.size": "1000"
          }' \
     http://localhost:8083/connectors/replicate-onprem-to-cloud/config | jq .

log "Start to inject lot of data"
docker exec broker kafka-producer-perf-test --topic products --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker:9092

sleep 30

log "Restart connector with small batch.size"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-onprem-to-cloud",
          "src.kafka.bootstrap.servers": "broker:9092",
          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"501",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "products",
          "topic.config.sync": false,
          "topic.auto.create": false,

          "producer.override.batch.size": "1000"
          }' \
     http://localhost:8083/connectors/replicate-onprem-to-cloud/config | jq .


# [2022-03-11 13:04:14,552] INFO [Worker clientId=sainsburys.applications.sc-ce-connect, groupId=sainsburys.applications.sc-ce-connect] (Re-)joining group (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator)
# [2022-03-11 13:04:14,558] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,558] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,559] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,559] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,559] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,560] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,560] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,561] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,562] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,563] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,564] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,565] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,566] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-11 13:04:14,566] ERROR WorkerSourceTask{id=replicate-onprem-to-cloud-0} failed to send record to products:  (org.apache.kafka.connect.runtime.WorkerSourceTask)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:760)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:747)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:283)
# 	at java.base/java.lang.Thread.run(Thread.java:829)

exit 0

log "Verify we have received the data in products topic"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-console-consumer --topic products --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --from-beginning --max-messages 10'