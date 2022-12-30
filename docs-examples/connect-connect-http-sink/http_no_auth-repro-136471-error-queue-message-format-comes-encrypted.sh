#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-136471-error-queue-message-format-comes-encrypted.yml"


log "Sending messages to topic http-messages"
# Using Heredoc
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages << EOF
{"record":"record1"}
EOF

log "-------------------------------------"
log "Running Simple (No) Authentication Example"
log "-------------------------------------"

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable":"false",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "retry.backoff.ms": "300",
               "retry.on.status.codes": "400-",
               "behavior.on.null.values": "ignore",
               "behavior.on.error": "log",
               "batch.max.size": "1",
               "http.api.url": "http://httpstat.us/404",
               "batch.max.size": "1",
               "batch.json.as.array": "false",
               "request.body.format": "json",
               "max.retries": "1",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "report.errors.as": "error_string"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

log "Check the error-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic error-responses --from-beginning --max-messages 1 --property print.headers=true

#input_record_offset:0,input_record_timestamp:1672245022561,input_record_partition:0,input_record_topic:http-messages,error_message:null,exception:null,response_content:404 Not Found,status_code:404,payload:1,reason_phrase:Not Found,url:http://httpstat.us/404    "Retry time lapsed, unable to process HTTP request. HTTP Response code: 404, Reason phrase: Not Found, Url: http://httpstat.us/404, Response content: 404 Not Found, Exception: null, Error message: null"

# [
#   {
#     "topic": "error-responses",
#     "partition": 0,
#     "offset": 0,
#     "timestamp": 1672395046211,
#     "timestampType": "CREATE_TIME",
#     "headers": [
#       {
#         "key": "input_record_offset",
#         "stringValue": "0"
#       },
#       {
#         "key": "input_record_timestamp",
#         "stringValue": "1672395040648"
#       },
#       {
#         "key": "input_record_partition",
#         "stringValue": "0"
#       },
#       {
#         "key": "input_record_topic",
#         "stringValue": "http-messages"
#       },
#       {
#         "key": "error_message",
#         "stringValue": null
#       },
#       {
#         "key": "exception",
#         "stringValue": null
#       },
#       {
#         "key": "response_content",
#         "stringValue": "404 Not Found"
#       },
#       {
#         "key": "status_code",
#         "stringValue": "404"
#       },
#       {
#         "key": "payload",
#         "stringValue": "{\"record\":\"record1\"}"
#       },
#       {
#         "key": "reason_phrase",
#         "stringValue": "Not Found"
#       },
#       {
#         "key": "url",
#         "stringValue": "http://httpstat.us/404"
#       }
#     ],
#     "key": null,
#     "value": "\"Retry time lapsed, unable to process HTTP request. HTTP Response code: 404, Reason phrase: Not Found, Url: http://httpstat.us/404, Response content: 404 Not Found, Exception: null, Error message: null\"",
#     "__confluent_index": 0
#   }
# ]

log "Creating http-sink-error connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "error-responses",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable":"false",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses-error",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses-error",
               "reporter.result.topic.replication.factor": 1,
               "retry.backoff.ms": "300",
               "retry.on.status.codes": "400-",
               "behavior.on.null.values": "ignore",
               "behavior.on.error": "log",
               "batch.max.size": "1",
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "batch.max.size": "1",
               "max.retries": "1",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "report.errors.as": "error_string",
               "request.body.format": "json",
               "batch.json.as.array": "false",
               "header.separator": "|",
               "headers": "Content-Type:application/json|Accept:application/json|payload:${key}"
          }' \
     http://localhost:8083/connectors/http-sink-error/config | jq .

sleep 3

log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . 

# 2022-12-30 10:21:46.309  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'content-type' = application/json
# 2022-12-30 10:21:46.311  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'accept' = application/json
# 2022-12-30 10:21:46.311  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'payload' = ${key}
# 2022-12-30 10:21:46.311  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'input_record_offset' = 0
# 2022-12-30 10:21:46.311  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'input_record_timestamp' = 1672395040648
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'input_record_partition' = 0
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'input_record_topic' = http-messages
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'error_message' = 
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'exception' = 
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'response_content' = 404 Not Found
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'status_code' = 404
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'reason_phrase' = Not Found
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'url' = http://httpstat.us/404
# 2022-12-30 10:21:46.312  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'content-length' = 202
# 2022-12-30 10:21:46.313  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'host' = http-service-no-auth:8080
# 2022-12-30 10:21:46.313  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'connection' = Keep-Alive
# 2022-12-30 10:21:46.313  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'user-agent' = Apache-HttpClient/4.5.13 (Java/11.0.16.1)
# 2022-12-30 10:21:46.313  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : Header 'accept-encoding' = gzip,deflate
# 2022-12-30 10:21:46.313  INFO 1 --- [nio-8080-exec-6] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: "Retry time lapsed, unable to process HTTP request. HTTP Response code: 404, Reason phrase: Not Found, Url: http://httpstat.us/404, Response content: 404 Not Found, Exception: null, Error message: null"


log "Check the success-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses-error --from-beginning --max-messages 1 --property print.headers=true