#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-110587-http-sink-connector-retry-in-case-of-timeout.yml"


log "Sending messages to topic http-messages"
seq 1 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

log "Creating http-sink connectorn server will return after timeout 30 seconds (http://httpstat.us/200?sleep=31000) and  behavior.on.error log"
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
          "http.api.url": "http://httpstat.us/200?sleep=31000",
          "batch.max.size": "1",
          "errors.tolerance": "all",
          "errors.deadletterqueue.topic.name": "dlq",
          "errors.deadletterqueue.topic.replication.factor": "1",

          "behavior.on.null.values": "ignore",
          "behavior.on.error": "log",
          "report.errors.as": "error_string",
          "headers": "Content-Type :application/json|Accept :application/json",
          "http.connect.timeout.ms": "30000",
          "http.request.timeout.ms": "30000",
          "max.retries": "2",
          "retry.backoff.ms": "30000",
          "retry.on.status.codes": "400-",
          "request.body.format": "string"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 60

# with "behavior.on.error": "log"
# [2022-06-21 14:04:04,857] ERROR [http-sink|task-0] Error while processing HTTP request with Url : http://httpstat.us/200?sleep=31000, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out (io.confluent.connect.http.writer.HttpWriterImpl:399)


log "Check the error-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic error-responses --from-beginning --property print.headers=true --max-messages 1

# input_record_offset:0,input_record_timestamp:1655820209237,input_record_partition:0,input_record_topic:http-messages,error_message:Exception while processing HTTP request for a batch of 1 records.,exception:Error while processing HTTP request with Url : http://httpstat.us/200?sleep=31000, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:382)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:301)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:275)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:177)
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
# ,response_content:null,status_code:null,payload:1,reason_phrase:null,url:http://httpstat.us/200?sleep=31000     "Retry time lapsed, unable to process HTTP request. HTTP Response code: null, Reason phrase: null, Url: http://httpstat.us/200?sleep=31000, Response content: null, Exception: java.net.SocketTimeoutException: Read timed out, Error message: Exception while processing HTTP request for a batch of 1 records."

curl http://localhost:8083/connectors?expand=status&expand=info | jq .

# ALL RUNNING

log "Sending messages to topic http-messages2"
seq 1 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages2

log "Creating http-sink connectorn server will return after timeout 30 seconds (http://httpstat.us/200?sleep=31000) and  behavior.on.error fail"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages2",
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
          "http.api.url": "http://httpstat.us/200?sleep=31000",
          "batch.max.size": "1",
          "errors.tolerance": "all",
          "errors.deadletterqueue.topic.name": "dlq",
          "errors.deadletterqueue.topic.replication.factor": "1",

          "behavior.on.null.values": "ignore",
          "behavior.on.error": "fail",
          "report.errors.as": "error_string",
          "headers": "Content-Type :application/json|Accept :application/json",
          "http.connect.timeout.ms": "30000",
          "http.request.timeout.ms": "30000",
          "max.retries": "2",
          "retry.backoff.ms": "30000",
          "retry.on.status.codes": "400-",
          "request.body.format": "string"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 60

# "behavior.on.error": "fail"
# [2022-06-21 14:05:13,097] ERROR [http-sink|task-0] WorkerSinkTask{id=http-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://httpstat.us/200?sleep=31000, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out
# 	at io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:397)
# 	at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:280)
# 	at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:177)
# 	at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
# 	at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
# 	... 10 more
# Caused by: Error while processing HTTP request with Url : http://httpstat.us/200?sleep=31000, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out
# 	at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:382)
# 	at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:301)
# 	at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:275)
# 	... 13 more


log "Check the error-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic error-responses --from-beginning --property print.headers=true --max-messages 2

# input_record_offset:0,input_record_timestamp:1655820278744,input_record_partition:0,input_record_topic:http-messages2,error_message:Exception while processing HTTP request for a batch of 1 records.,exception:Error while processing HTTP request with Url : http://httpstat.us/200?sleep=31000, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:382)
#         at io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:301)
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:275)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:177)
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
# ,response_content:null,status_code:null,payload:1,reason_phrase:null,url:http://httpstat.us/200?sleep=31000     "Retry time lapsed, unable to process HTTP request. HTTP Response code: null, Reason phrase: null, Url: http://httpstat.us/200?sleep=31000, Response content: null, Exception: java.net.SocketTimeoutException: Read timed out, Error message: Exception while processing HTTP request for a batch of 1 records."

curl http://localhost:8083/connectors?expand=status&expand=info | jq .

     #  "tasks": [
     #    {
     #      "id": 0,
     #      "state": "FAILED",
     #      "worker_id": "connect:8083",
     #      "trace": "org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://httpstat.us/200?sleep=31000, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out\n\tat io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:397)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:280)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:177)\n\tat io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)\n\t... 10 more\nCaused by: Error while processing HTTP request with Url : http://httpstat.us/200?sleep=31000, Error Message : Exception while processing HTTP request for a batch of 1 records., Exception : java.net.SocketTimeoutException: Read timed out\n\tat io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:382)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:301)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:275)\n\t... 13 more\n"
     #    }
     #  ],
     #  "type": "sink"

# log "Check the success-responses topic"
# timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 10 --property print.headers=true


log "Sending messages to topic http-messages3"
seq 1 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages3

log "Creating http-sink connectorn server will return error 404 (http://httpstat.us/404) and behavior.on.error log"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages3",
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
          "http.api.url": "http://httpstat.us/404",
          "batch.max.size": "1",
          "errors.tolerance": "all",
          "errors.deadletterqueue.topic.name": "dlq",
          "errors.deadletterqueue.topic.replication.factor": "1",

          "behavior.on.null.values": "ignore",
          "behavior.on.error": "log",
          "report.errors.as": "error_string",
          "headers": "Content-Type :application/json|Accept :application/json",
          "http.connect.timeout.ms": "30000",
          "http.request.timeout.ms": "30000",
          "max.retries": "2",
          "retry.backoff.ms": "30000",
          "retry.on.status.codes": "400-",
          "request.body.format": "string"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 60

# with "behavior.on.error": "log"
# [2022-06-21 14:23:20,096] ERROR [http-sink|task-0] Error while processing HTTP request with Url : http://httpstat.us/404, Status code : 404, Reason Phrase : Not Found, Response Content : {"code":404,"description":"Not Found"},  (io.confluent.connect.http.writer.HttpWriterImpl:399)

log "Check the error-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic error-responses --from-beginning --property print.headers=true --max-messages 3


# input_record_offset:0,input_record_timestamp:1655821339999,input_record_partition:0,input_record_topic:http-messages3,error_message:null,exception:null,response_content:{"code":404,"description":"Not Found"},status_code:404,payload:1,reason_phrase:Not Found,url:http://httpstat.us/404  "Retry time lapsed, unable to process HTTP request. HTTP Response code: 404, Reason phrase: Not Found, Url: http://httpstat.us/404, Response content: {\"code\":404,\"description\":\"Not Found\"}, Exception: null, Error message: null"

curl http://localhost:8083/connectors?expand=status&expand=info | jq .

# RUNNING




log "Sending messages to topic http-messages4"
seq 1 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages4

log "Creating http-sink connectorn server will return error 404 (http://httpstat.us/404) and behavior.on.error fail"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages4",
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
          "http.api.url": "http://httpstat.us/404",
          "batch.max.size": "1",
          "errors.tolerance": "all",
          "errors.deadletterqueue.topic.name": "dlq",
          "errors.deadletterqueue.topic.replication.factor": "1",

          "behavior.on.null.values": "ignore",
          "behavior.on.error": "fail",
          "report.errors.as": "error_string",
          "headers": "Content-Type :application/json|Accept :application/json",
          "http.connect.timeout.ms": "30000",
          "http.request.timeout.ms": "30000",
          "max.retries": "2",
          "retry.backoff.ms": "30000",
          "retry.on.status.codes": "400-",
          "request.body.format": "string"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 60

# with "behavior.on.error": "fail"
# [2022-06-21 14:23:20,096] ERROR [http-sink|task-0] Error while processing HTTP request with Url : http://httpstat.us/404, Status code : 404, Reason Phrase : Not Found, Response Content : {"code":404,"description":"Not Found"},  (io.confluent.connect.http.writer.HttpWriterImpl:399)

log "Check the error-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic error-responses --from-beginning --property print.headers=true --max-messages 4


# input_record_offset:0,input_record_timestamp:1655821635121,input_record_partition:0,input_record_topic:http-messages4,error_message:null,exception:null,response_content:{"code":404,"description":"Not Found"},status_code:404,payload:1,reason_phrase:Not Found,url:http://httpstat.us/404  "Retry time lapsed, unable to process HTTP request. HTTP Response code: 404, Reason phrase: Not Found, Url: http://httpstat.us/404, Response content: {\"code\":404,\"description\":\"Not Found\"}, Exception: null, Error message: null"

curl http://localhost:8083/connectors?expand=status&expand=info | jq .

#           "state": "FAILED",
          # "worker_id": "connect:8083",
          # "trace": "org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: org.apache.kafka.connect.errors.ConnectException: Error while processing HTTP request with Url : http://httpstat.us/404, Status code : 404, Reason Phrase : Not Found, Response Content : {\"code\":404,\"description\":\"Not Found\"}, \n\tat io.confluent.connect.http.writer.HttpWriterImpl.handleException(HttpWriterImpl.java:397)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:280)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:177)\n\tat io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)\n\t... 10 more\nCaused by: Error while processing HTTP request with Url : http://httpstat.us/404, Status code : 404, Reason Phrase : Not Found, Response Content : {\"code\":404,\"description\":\"Not Found\"}, \n\tat io.confluent.connect.http.writer.HttpWriterImpl.executeBatchRequest(HttpWriterImpl.java:368)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.executeRequestWithBackOff(HttpWriterImpl.java:301)\n\tat io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:275)\n\t... 13 more\n"