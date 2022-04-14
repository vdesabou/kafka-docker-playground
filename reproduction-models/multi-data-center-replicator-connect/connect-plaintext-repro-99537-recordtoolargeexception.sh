#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh "$PWD/docker-compose.mdc-plaintext.repro-99537-recordtoolargeexception.yml"

log "Sending small messages in europe"
seq -f "abc%g" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE"

sleep 10

log "Sending bigger messages in europe"
seq -f "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx%g" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE"

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

          "producer.override.max.request.size": "100"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

# [2022-04-14 13:47:41,076] ERROR [replicate-europe-to-us|task-0] WorkerSourceTask{id=replicate-europe-to-us-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:187)
# org.apache.kafka.connect.errors.ConnectException: Unrecoverable exception from producer send callback
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.maybeThrowProducerSendException(WorkerSourceTask.java:282)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:336)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:264)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:185)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:834)
# Caused by: org.apache.kafka.common.errors.RecordTooLargeException: The message is 155 bytes when serialized which is larger than 100, which is the value of the max.request.size configuration.

exit 0


log "restarting task"
docker container exec connect-us curl -X POST localhost:8083/connectors/replicate-europe-to-us/tasks/0/restart

exit 0
sleep 120

log "Verify we have received the data in all the sales_ topics in the US"
docker container exec -i connect-us bash -c " kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_.*' --from-beginning"



# docker container exec -i control-center bash -c "control-center-console-consumer /etc/confluent-control-center/control-center.properties --topic --from-beginning _confluent-monitoring"

