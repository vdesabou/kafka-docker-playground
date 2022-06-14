#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-109687--retry-loop-while-receiving-500--error-from-the-target.yml"


log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

log "-------------------------------------"
log "Running OAuth2 Authentication Example"
log "-------------------------------------"

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
               "http.api.url": "http://httpstat.us/500",
               "auth.type": "OAUTH2",
               "oauth2.token.url": "http://http-service-oauth2-auth:8080/oauth/token",
               "oauth2.client.id": "kc-client",
               "oauth2.client.secret": "kc-secret",

               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "max.retries": "1",
               "retry.backoff.ms": "3000",
               "request.body.format": "json",
               "batch.json.as.array": "false"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

# [2022-06-14 10:04:51,236] ERROR [http-sink|task-0] WorkerSinkTask{id=http-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Error while processing HTTP request with Url : http://httpstat.us/500, Status code : 500, Reason Phrase : Internal Server Error, Response Content : 500 Internal Server Error,  (org.apache.kafka.connect.runtime.WorkerSinkTask:616)
# org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://httpstat.us/500, Status code : 500, Reason Phrase : Internal Server Error, Response Content : 500 Internal Server Error, 
#         at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:399)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:282)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:179)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: Error while processing HTTP request with Url : http://httpstat.us/500, Status code : 500, Reason Phrase : Internal Server Error, Response Content : 500 Internal Server Error, 
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:370)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:303)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:277)
#         ... 13 more
# [2022-06-14 10:04:51,239] ERROR [http-sink|task-0] WorkerSinkTask{id=http-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://httpstat.us/500, Status code : 500, Reason Phrase : Internal Server Error, Response Content : 500 Internal Server Error, 
#         at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:399)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:282)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:179)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more
# Caused by: Error while processing HTTP request with Url : http://httpstat.us/500, Status code : 500, Reason Phrase : Internal Server Error, Response Content : 500 Internal Server Error, 
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:370)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:303)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:277)
#         ... 13 more
# [2022-06-14 10:04:51,240] INFO [http-sink|task-0] Stopping HttpSinkTask (io.confluent.connect.http.HttpSinkTask:72)

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X POST \
  http://localhost:10080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


log "Confirm that the data was sent to the HTTP endpoint."
curl -X GET \
    http://localhost:10080/api/messages \
    -H "Authorization: Bearer ${token}" | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log
