#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Sending messages to topic http-messages"
seq 10 | docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

echo "-------------------------------------"
echo "Running Simple (No) Authentication Example"
echo "-------------------------------------"

echo "Creating HttpSinkNoAuthTestRetry connector"

# the HTTP server will always reply INTERNAL_SERVER_ERROR(500)
# we set retry.backoff.ms: 15000 and max.retries: 3
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
          "name": "HttpSinkNoAuthTestRetry",
          "config": {
               "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "http.api.url": "http://http-service-no-auth-500:8080/api/messages",
               "retry.backoff.ms": 15000,
               "max.retries": 3
          }}' \
     http://localhost:8083/connectors | jq .


# we get:

# 2019-10-10 14:28:04.732  INFO 1 --- [nio-8080-exec-2] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: 1
# 2019-10-10 14:28:20.139  INFO 1 --- [nio-8080-exec-4] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: 1
# 2019-10-10 14:28:35.154  INFO 1 --- [nio-8080-exec-7] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: 1
# 2019-10-10 14:28:50.163  INFO 1 --- [nio-8080-exec-8] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: 1




# [2019-10-10 14:28:05,130] WARN Write of 10 records failed, remainingRetries=3 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":1,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2019-10-10 14:28:05,134] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":1,"message":"1"}
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:79)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":1,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 14:28:20,146] WARN Write of 10 records failed, remainingRetries=2 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":2,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2019-10-10 14:28:20,146] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":2,"message":"1"}
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:79)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":2,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 14:28:35,159] WARN Write of 10 records failed, remainingRetries=1 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":3,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2019-10-10 14:28:35,159] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":3,"message":"1"}
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:79)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":3,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 14:28:50,170] WARN Write of 10 records failed, remainingRetries=0 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2019-10-10 14:28:50,170] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"1"}
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:75)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 14:28:50,171] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:560)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:321)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:224)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:192)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:177)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:227)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"1"}
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:75)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         ... 10 more
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 14:28:50,172] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# [2019-10-10 14:28:50,172] INFO Stopping task (io.confluent.connect.http.HttpSinkTask)





# at the end
# curl localhost:9082/api/messages | jq .
# [
#   {
#     "id": 1,
#     "message": "1"
#   },
#   {
#     "id": 2,
#     "message": "1"
#   },
#   {
#     "id": 3,
#     "message": "1"
#   },
#   {
#     "id": 4,
#     "message": "1"
#   }
# ]
