#!/bin/bash
set -e

# force 5.5.6
export TAG=5.5.6

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker compose down -v --remove-orphans
docker compose up -d --quiet-pull
${DIR}/wait_container_ready "connect1"
${DIR}/wait_container_ready "connect2"
${DIR}/wait_container_ready "connect3"

docker exec broker1 kafka-topics --create --topic test-topic --partitions 10 --replication-factor 3 --bootstrap-server broker:9092

log "Sending messages to topic test-topic"
seq 10 | docker exec -i broker1 kafka-console-producer --bootstrap-server broker1:9092 --topic test-topic

log "Creating Replicator connector"
playground connector create-or-update --connector replicator  << EOF
{
              "tasks.max": "10",
              "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
               "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "src.consumer.group.id": "duplicate-topic",
               "confluent.topic.replication.factor": 3,
               "provenance.header.enable": true,
               "topic.whitelist": "test-topic",
               "topic.rename.format": "test-topic-duplicate",
               "dest.kafka.bootstrap.servers": "broker1:9092,broker2:9092,broker3:9092",
               "src.kafka.bootstrap.servers": "broker1:9092,broker2:9092,broker3:9092"
           }
EOF

sleep 10

log "Verify we have received the data in test-topic-duplicate topic"
playground topic consume --topic test-topic-duplicate --min-expected-messages 10 --timeout 60

sleep 5

log "Getting tasks placement"

curl --request GET \
  --url http://localhost:8083/connectors/replicator/status \
  --header 'accept: application/json' | jq


log "Pausing broker 1"
docker container pause broker1
#--> don't do stop otherwise geeting WARN Couldn't resolve server broker1:9092 from bootstrap.servers as DNS resolution failed for broker1 (org.apache.kafka.clients.ClientUtils)
# docker exec -i --privileged --user root broker1 bash -c "apt-get update && apt-get install iptables -y"
# docker exec -i --privileged --user root broker1 bash -c "iptables -A INPUT -p tcp --destination-port 9092 -j REJECT"
# docker exec -i --privileged --user root broker1 bash -c "iptables -A OUTPUT -p tcp --destination-port 9092 -j REJECT"
# docker exec -i --privileged --user root broker1 bash -c "iptables -L -n -v"

docker container stop connect2

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/replicator/status \
  --header 'accept: application/json' | jq

docker container start connect2

# commented as eager is used
# log "sleep 5 minutes (scheduled.rebalance.max.delay.ms), after this time all tasks should be RUNNING (no more UNASSIGNED)"
# sleep 310
sleep 60

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/replicator/status \
  --header 'accept: application/json' | jq

# connect2 (CP 5.5.3):
# [2021-02-24 23:18:35,425] INFO [AdminClient clientId=adminclient-4] Metadata update failed (org.apache.kafka.clients.admin.internals.AdminMetadataManager)
# org.apache.kafka.common.errors.TimeoutException: Call(callName=fetchMetadata, deadlineMs=1614208715423) timed out at 1614208715424 after 1 attempt(s)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting to send the call.
# [2021-02-24 23:19:05,118] WARN [Producer clientId=producer-1] Bootstrap broker broker1:9092 (id: -1 rack: null) disconnected (org.apache.kafka.clients.NetworkClient)
# [2021-02-24 23:19:05,224] INFO [Producer clientId=producer-1] Cluster ID: BeW7m24rSb6PSJADreaW9w (org.apache.kafka.clients.Metadata)
# [2021-02-24 23:19:05,429] INFO [AdminClient clientId=adminclient-4] Metadata update failed (org.apache.kafka.clients.admin.internals.AdminMetadataManager)
# org.apache.kafka.common.errors.TimeoutException: Call(callName=fetchMetadata, deadlineMs=1614208745424) timed out at 9223372036854775807 after 1 attempt(s)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting to send the call.
# [2021-02-24 23:19:05,431] ERROR [Worker clientId=connect-1, groupId=connect-cluster] Uncaught exception in herder work thread, exiting:  (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# org.apache.kafka.connect.errors.ConnectException: Timed out while checking for or creating topic(s) 'connect-configs'. This could indicate a connectivity issue, unavailable topic partitions, or if this is your first use of the topic it may have taken too long to create.
# 	at org.apache.kafka.connect.util.TopicAdmin.createTopics(TopicAdmin.java:258)
# 	at org.apache.kafka.connect.storage.KafkaConfigBackingStore$1.run(KafkaConfigBackingStore.java:484)
# 	at org.apache.kafka.connect.util.KafkaBasedLog.start(KafkaBasedLog.java:130)
# 	at org.apache.kafka.connect.storage.KafkaConfigBackingStore.start(KafkaConfigBackingStore.java:265)
# 	at org.apache.kafka.connect.runtime.AbstractHerder.startServices(AbstractHerder.java:125)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.run(DistributedHerder.java:288)
# 	at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
# 	at java.util.concurrent.FutureTask.run(FutureTask.java:266)
# 	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
# 	at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
# 	at java.lang.Thread.run(Thread.java:748)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Call(callName=createTopics, deadlineMs=1614208745422) timed out at 1614208745423 after 1 attempt(s)
# Caused by: org.apache.kafka.common.errors.TimeoutException: Timed out waiting for a node assignment.

#    curl --request GET \
# >     --url http://localhost:8083/connectors/replicator/status \
# >     --header 'accept: application/json' | jq
#   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
#                                  Dload  Upload   Total   Spent    Left  Speed
# 100  2643  100  2643    0     0  94392      0 --:--:-- --:--:-- --:--:-- 94392
# {
#   "name": "replicator",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect3:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "RUNNING",
#       "worker_id": "connect3:8083"
#     },
#     {
#       "id": 1,
#       "state": "FAILED",
#       "worker_id": "connect3:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: Failed to obtain source cluster ID, please restart the source Kafka cluster\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.setClusterIds(ReplicatorSourceTask.java:380)\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.start(ReplicatorSourceTask.java:301)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:219)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)\n\tat java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)\n\tat java.util.concurrent.FutureTask.run(FutureTask.java:266)\n\tat java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)\n\tat java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)\n\tat java.lang.Thread.run(Thread.java:748)\n"
#     },
#     {
#       "id": 2,
#       "state": "RUNNING",
#       "worker_id": "connect3:8083"
#     },
#     {
#       "id": 3,
#       "state": "FAILED",
#       "worker_id": "connect3:8083",
#       "trace": "org.apache.kafka.common.errors.TimeoutException: Timeout of 60000ms expired before the last committed offset for partitions [test-topic-2, __consumer_timestamps-12, __consumer_timestamps-42, __consumer_timestamps-22, __consumer_timestamps-2, __consumer_timestamps-32] could be determined. Try tuning default.api.timeout.ms larger to relax the threshold.\n"
#     },
#     {
#       "id": 4,
#       "state": "RUNNING",
#       "worker_id": "connect3:8083"
#     },
#     {
#       "id": 5,
#       "state": "RUNNING",
#       "worker_id": "connect3:8083"
#     },
#     {
#       "id": 6,
#       "state": "FAILED",
#       "worker_id": "connect3:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: Failed to obtain source cluster ID, please restart the source Kafka cluster\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.setClusterIds(ReplicatorSourceTask.java:380)\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.start(ReplicatorSourceTask.java:301)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:219)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)\n\tat java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)\n\tat java.util.concurrent.FutureTask.run(FutureTask.java:266)\n\tat java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)\n\tat java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)\n\tat java.lang.Thread.run(Thread.java:748)\n"
#     },
#     {
#       "id": 7,
#       "state": "FAILED",
#       "worker_id": "connect3:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: Failed to obtain source cluster ID, please restart the source Kafka cluster\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.setClusterIds(ReplicatorSourceTask.java:380)\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.start(ReplicatorSourceTask.java:301)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:219)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)\n\tat java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)\n\tat java.util.concurrent.FutureTask.run(FutureTask.java:266)\n\tat java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)\n\tat java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)\n\tat java.lang.Thread.run(Thread.java:748)\n"
#     },
#     {
#       "id": 8,
#       "state": "FAILED",
#       "worker_id": "connect3:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: Failed to obtain source cluster ID, please restart the source Kafka cluster\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.setClusterIds(ReplicatorSourceTask.java:380)\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.start(ReplicatorSourceTask.java:301)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:219)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)\n\tat java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)\n\tat java.util.concurrent.FutureTask.run(FutureTask.java:266)\n\tat java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)\n\tat java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)\n\tat java.lang.Thread.run(Thread.java:748)\n"
#     },
#     {
#       "id": 9,
#       "state": "FAILED",
#       "worker_id": "connect3:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: Failed to obtain source cluster ID, please restart the source Kafka cluster\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.setClusterIds(ReplicatorSourceTask.java:380)\n\tat io.confluent.connect.replicator.ReplicatorSourceTask.start(ReplicatorSourceTask.java:301)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:219)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:235)\n\tat java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)\n\tat java.util.concurrent.FutureTask.run(FutureTask.java:266)\n\tat java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)\n\tat java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)\n\tat java.lang.Thread.run(Thread.java:748)\n"
#     }
#   ],
#   "type": "source"
# }


# connect2 (CP 6.1.0)
# [2021-02-24 23:40:32,262] ERROR [Producer clientId=producer-2] Interrupted while joining ioThread (org.apache.kafka.clients.producer.KafkaProducer)
# java.lang.InterruptedException
# 	at java.base/java.lang.Object.wait(Native Method)
# 	at java.base/java.lang.Thread.join(Thread.java:1313)
# 	at org.apache.kafka.clients.producer.KafkaProducer.close(KafkaProducer.java:1221)
# 	at org.apache.kafka.clients.producer.KafkaProducer.close(KafkaProducer.java:1198)
# 	at org.apache.kafka.clients.producer.KafkaProducer.close(KafkaProducer.java:1174)
# 	at org.apache.kafka.connect.util.KafkaBasedLog.stop(KafkaBasedLog.java:190)
# 	at org.apache.kafka.connect.storage.KafkaStatusBackingStore.stop(KafkaStatusBackingStore.java:228)
# 	at org.apache.kafka.connect.runtime.AbstractHerder.stopServices(AbstractHerder.java:134)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.halt(DistributedHerder.java:676)
# 	at org.apache.kafka.connect.runtime.distributed.DistributedHerder.run(DistributedHerder.java:298)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:834)
# [2021-02-24 23:40:32,265] INFO [Producer clientId=producer-2] Proceeding to force close the producer since pending requests could not be completed within timeout 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer)
# [2021-02-24 23:40:32,263] INFO [Worker clientId=connect-1, groupId=connect-cluster] Herder stopped (org.apache.kafka.connect.runtime.distributed.DistributedHerder)
# [2021-02-24 23:40:32,265] INFO Kafka Connect stopped (org.apache.kafka.connect.runtime.Connect)
# [2021-02-24 23:40:32,266] ERROR Failed to write status update (org.apache.kafka.connect.storage.KafkaStatusBackingStore)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:748)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:735)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:280)
# 	at java.base/java.lang.Thread.run(Thread.java:834)
# [2021-02-24 23:40:32,266] INFO Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics)
# [2021-02-24 23:40:32,266] INFO Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics)
# [2021-02-24 23:40:32,266] ERROR Failed to write status update (org.apache.kafka.connect.storage.KafkaStatusBackingStore)
# org.apache.kafka.common.KafkaException: Producer is closed forcefully.
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortBatches(RecordAccumulator.java:748)
# 	at org.apache.kafka.clients.producer.internals.RecordAccumulator.abortIncompleteBatches(RecordAccumulator.java:735)
# 	at org.apache.kafka.clients.producer.internals.Sender.run(Sender.java:280)
# 	at java.base/java.lang.Thread.run(Thread.java:834)