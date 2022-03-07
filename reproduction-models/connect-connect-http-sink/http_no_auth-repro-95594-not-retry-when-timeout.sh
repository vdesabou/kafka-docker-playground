#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-95594-not-retry-when-timeout.yml"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.http \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-no-auth:8080/api/messages",

               "behavior.on.null.values": "ignore",
               "behavior.on.error": "ignore",
               "errors.retry.timeout": "-1",
               "max.retries": "1"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .

sleep 5

log "Blocking traffic"
IP=$(docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker ps -aq) | grep http-service-no-auth | cut -d " " -f 3)
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp -s $IP -j DROP"

log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

# What I observe if that the connector does retry, but DEBUG traces needs to be set to see the retries:

# [2022-03-07 10:44:29,042] DEBUG [http-sink|task-0] Backing off after failing to execute HTTP request for 1 records (io.confluent.connect.http.writer.HttpWriterImpl:316)
# Error while processing HTTP request with Url : http://http-service-no-auth:8080/api/messages, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : org.apache.http.conn.ConnectTimeoutException: Connect to http-service-no-auth:8080 [http-service-no-auth/192.168.96.2] failed: connect timed out
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:384)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:303)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:277)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:179)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Then it will retry 10 times as per max.retries

# max.retries
# The maximum number of times to retry on errors before failing the task.
# Type: int
# Default: 10
# Valid Values: [1,…]
# Importance: medium

# At the end of the retries, the task will fail:

# [2022-03-07 10:53:59,365] ERROR [http-sink|task-0] WorkerSinkTask{id=http-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Error while processing HTTP request with Url : http://http-service-no-auth:8080/api/messages, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : org.apache.http.conn.ConnectTimeoutException: Connect to http-service-no-auth:8080 [http-service-no-auth/192.168.96.2] failed: connect timed out (org.apache.kafka.connect.runtime.WorkerSinkTask:636)
# org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://http-service-no-auth:8080/api/messages, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : org.apache.http.conn.ConnectTimeoutException: Connect to http-service-no-auth:8080 [http-service-no-auth/192.168.96.2] failed: connect timed out
#         at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:399)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:282)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:179)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: Error while processing HTTP request with Url : http://http-service-no-auth:8080/api/messages, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : org.apache.http.conn.ConnectTimeoutException: Connect to http-service-no-auth:8080 [http-service-no-auth/192.168.96.2] failed: connect timed out
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:384)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:303)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:277)
#         ... 13 more
# [2022-03-07 10:53:59,366] WARN [http-sink|task-0] WorkerSinkTask{id=http-sink-0} After being scheduled for shutdown, the orphan task threw an uncaught exception. A newer instance of this task might be already running (org.apache.kafka.connect.runtime.WorkerTask:202)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://http-service-no-auth:8080/api/messages, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : org.apache.http.conn.ConnectTimeoutException: Connect to http-service-no-auth:8080 [http-service-no-auth/192.168.96.2] failed: connect timed out
#         at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:399)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:282)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:179)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: Error while processing HTTP request with Url : http://http-service-no-auth:8080/api/messages, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : org.apache.http.conn.ConnectTimeoutException: Connect to http-service-no-auth:8080 [http-service-no-auth/192.168.96.2] failed: connect timed out
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:384)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:303)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:277)
#         ... 13 more
