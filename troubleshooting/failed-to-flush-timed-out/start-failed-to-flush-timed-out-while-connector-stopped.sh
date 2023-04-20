#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.failed-to-flush-timed-out-while-connector-stopped.yml"
log "Generating data"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL -k 'https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80' -o /tmp/kafka-connect/examples/file.json"

docker exec --privileged --user root -i broker yum install -y libmnl
docker exec --privileged --user root -i broker bash -c 'wget http://vault.centos.org/8.1.1911/BaseOS/x86_64/os/Packages/iproute-tc-4.18.0-15.el8.x86_64.rpm && rpm -i --nodeps --nosignature http://vault.centos.org/8.1.1911/BaseOS/x86_64/os/Packages/iproute-tc-4.18.0-15.el8.x86_64.rpm'

log "Adding latency"
add_latency broker connect 1000ms

log "Creating FileStream Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
               "topic": "filestream",
               "file": "/tmp/kafka-connect/examples/file.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/filestream-source/config | jq .


sleep 5

log "Deleting connector"
curl --request DELETE \
  --url http://localhost:8083/connectors/filestream-source

log "Verify we have received the data in filestream topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic filestream --from-beginning --max-messages 10

# [2022-01-11 11:42:15,286] INFO [filestream-source|task-0] WorkerSourceTask{id=filestream-source-0} Committing offsets (org.apache.kafka.connect.runtime.WorkerSourceTask:485)
# [2022-01-11 11:42:15,286] INFO [filestream-source|task-0] WorkerSourceTask{id=filestream-source-0} flushing 1 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:502)
# [2022-01-11 11:42:15,286] ERROR [filestream-source|task-0] WorkerSourceTask{id=filestream-source-0} Failed to flush, timed out while waiting for producer to flush outstanding 1 messages (org.apache.kafka.connect.runtime.WorkerSourceTask:509)
# [2022-01-11 11:42:15,287] ERROR [filestream-source|task-0] WorkerSourceTask{id=filestream-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:191)
# org.apache.kafka.connect.errors.ConnectException: Unrecoverable exception trying to send
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:402)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:256)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.common.KafkaException: Producer closed while send in progress
#         at org.apache.kafka.clients.producer.KafkaProducer.doSend(KafkaProducer.java:910)
#         at org.apache.kafka.clients.producer.KafkaProducer.send(KafkaProducer.java:886)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:368)
#         ... 8 more
# Caused by: org.apache.kafka.common.KafkaException: Requested metadata update after close
#         at org.apache.kafka.clients.producer.internals.ProducerMetadata.awaitUpdate(ProducerMetadata.java:127)
#         at org.apache.kafka.clients.producer.KafkaProducer.waitOnMetadata(KafkaProducer.java:1048)
#         at org.apache.kafka.clients.producer.KafkaProducer.doSend(KafkaProducer.java:907)
#         ... 10 more
# [2022-01-11 11:42:15,288] INFO [filestream-source|task-0] [Producer clientId=connect-worker-producer] Closing the Kafka producer with timeoutMillis = 30000 ms. (org.apache.kafka.clients.producer.KafkaProducer:1205)
