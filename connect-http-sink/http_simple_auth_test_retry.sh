#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Sending messages to topic http-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages << EOF
Message 1
EOF

echo "-------------------------------------"
echo "Running Simple (No) Authentication Example"
echo "-------------------------------------"

echo "Creating HttpSinkNoAuthTestRetry connector"

# the HTTP server will always reply INTERNAL_SERVER_ERROR(500)
# we set retry.backoff.ms: 15000 and max.retries: 3
docker exec connect \
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


sleep 5
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages << EOF
Message 2
EOF

#################################################
# we get with tasks.max=1:
#################################################

# 2019-10-10 15:02:17.183  INFO 1 --- [nio-8080-exec-2] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:02:32.486  INFO 1 --- [nio-8080-exec-3] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:02:47.505  INFO 1 --- [nio-8080-exec-4] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:03:02.534  INFO 1 --- [nio-8080-exec-5] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1



# [2019-10-10 15:02:17,476] WARN Write of 1 records failed, remainingRetries=3 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":1,"message":"Message 1"}
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
# [2019-10-10 15:02:17,478] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":1,"message":"Message 1"}
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
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":1,"message":"Message 1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 15:02:32,495] WARN Write of 1 records failed, remainingRetries=2 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":2,"message":"Message 1"}
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
# [2019-10-10 15:02:32,496] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":2,"message":"Message 1"}
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
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":2,"message":"Message 1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 15:02:47,514] WARN Write of 1 records failed, remainingRetries=1 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":3,"message":"Message 1"}
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
# [2019-10-10 15:02:47,514] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} RetriableException from SinkTask: (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.RetriableException: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":3,"message":"Message 1"}
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
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":3,"message":"Message 1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 15:03:02,557] WARN Write of 1 records failed, remainingRetries=0 (io.confluent.connect.http.HttpSinkTask)
# java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"Message 1"}
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
# [2019-10-10 15:03:02,558] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. (org.apache.kafka.connect.runtime.WorkerSinkTask)
# org.apache.kafka.connect.errors.ConnectException: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"Message 1"}
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
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"Message 1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 15:03:02,559] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask)
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
# Caused by: org.apache.kafka.connect.errors.ConnectException: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"Message 1"}
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:75)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:538)
#         ... 10 more
# Caused by: java.io.IOException: HTTP Response code: 500, , Submitted payload: Message 1, url:http://http-service-no-auth-500:8080/api/messages : {"id":4,"message":"Message 1"}
#         at io.confluent.connect.http.writer.HttpWriterImpl.sendBatch(HttpWriterImpl.java:170)
#         at io.confluent.connect.http.writer.HttpWriterImpl.write(HttpWriterImpl.java:117)
#         at io.confluent.connect.http.HttpSinkTask.put(HttpSinkTask.java:62)
#         ... 11 more
# [2019-10-10 15:03:02,559] ERROR WorkerSinkTask{id=HttpSinkNoAuthTestRetry-0} Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)



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


#################################################
# With tasks.max=2
#################################################


# we get:

# 2019-10-10 15:25:25.237  INFO 1 --- [nio-8080-exec-1] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:25:40.969  INFO 1 --- [nio-8080-exec-2] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:25:55.992  INFO 1 --- [nio-8080-exec-3] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:26:11.011  INFO 1 --- [nio-8080-exec-4] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:26:11.129  INFO 1 --- [nio-8080-exec-5] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:26:13.355  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1
# 2019-10-10 15:26:28.379  INFO 1 --- [nio-8080-exec-7] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: Message 1


# # task 1
# [2019-10-10 15:25:25,946] WARN Write of 2 records failed, remainingRetries=3 (io.confluent.connect.http.HttpSinkTask)
# [2019-10-10 15:25:40,980] WARN Write of 2 records failed, remainingRetries=2 (io.confluent.connect.http.HttpSinkTask)
# [2019-10-10 15:25:55,998] WARN Write of 2 records failed, remainingRetries=1 (io.confluent.connect.http.HttpSinkTask)
# [2019-10-10 15:26:11,017] WARN Write of 2 records failed, remainingRetries=0 (io.confluent.connect.http.HttpSinkTask)

# # task 2
# [2019-10-10 15:26:11,134] WARN Write of 2 records failed, remainingRetries=3 (io.confluent.connect.http.HttpSinkTask)
# [2019-10-10 15:26:13,367] WARN Write of 2 records failed, remainingRetries=2 (io.confluent.connect.http.HttpSinkTask)
# [2019-10-10 15:26:28,387] WARN Write of 2 records failed, remainingRetries=1 (io.confluent.connect.http.HttpSinkTask)
# [2019-10-10 15:26:43,413] WARN Write of 2 records failed, remainingRetries=0 (io.confluent.connect.http.HttpSinkTask)

# [
#   {
#     "id": 1,
#     "message": "Message 1"
#   },
#   {
#     "id": 2,
#     "message": "Message 1"
#   },
#   {
#     "id": 3,
#     "message": "Message 1"
#   },
#   {
#     "id": 4,
#     "message": "Message 1"
#   },
#   {
#     "id": 5,
#     "message": "Message 1"
#   },
#   {
#     "id": 6,
#     "message": "Message 1"
#   },
#   {
#     "id": 7,
#     "message": "Message 1"
#   },
#   {
#     "id": 8,
#     "message": "Message 1"
#   }
# ]
