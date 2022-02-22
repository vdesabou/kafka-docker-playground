#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

# schema
# {
#     "fields": [
#         {
#             "default": null,
#             "name": "userType",
#             "type": [
#                 "null",
#                 {
#                     "type": "string",
#                     "avro.java.string": "String"
#                 },
#                 {
#                     "name": "UserType",
#                     "symbols": [
#                         "ANONYMOUS",
#                         "REGISTERED"
#                     ],
#                     "type": "enum"
#                 }
#             ]
#         }
#     ],
#     "name": "EnumStringUnion",
#     "namespace": "com.connect.avro",
#     "type": "record"
# }
log "Send userType as string to topic myavrotopic1"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic1 --property value.schema='{"type":"record","name":"EnumStringUnion","namespace":"com.connect.avro","fields":[{"name":"userType","type":["null","string",{"type":"enum","name":"UserType","symbols":["ANONYMOUS","REGISTERED"]}],"default":null}]}' << EOF
{"userType":{"string":"anystring"}}
EOF

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "myavrotopic1",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry:8081",
          "value.converter.enhanced.avro.schema.support": "true",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "error-responses",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "success-responses",
          "reporter.result.topic.replication.factor": 1,
          "http.api.url": "http://http-service-basic-auth:8080/api/messages",
          "request.body.format": "json",
          "auth.type": "BASIC",
          "connection.user": "admin",
          "connection.password": "password"
          }' \
     http://localhost:8083/connectors/http-sink-1/config | jq .

sleep 4

curl localhost:8083/connectors/http-sink-1/status | jq

log "Send userType as enum to topic myavrotopic2"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic2 --property value.schema='{"type":"record","name":"EnumStringUnion","namespace":"com.connect.avro","fields":[{"name":"userType","type":["null","string",{"type":"enum","name":"UserType","symbols":["ANONYMOUS","REGISTERED"]}],"default":null}]}' << EOF
{"userType":{"com.connect.avro.UserType":"ANONYMOUS"}}
EOF

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "myavrotopic2",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry:8081",
          "value.converter.enhanced.avro.schema.support": "true",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "error-responses",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "success-responses",
          "reporter.result.topic.replication.factor": 1,
          "http.api.url": "http://http-service-basic-auth:8080/api/messages",
          "request.body.format": "json",
          "auth.type": "BASIC",
          "connection.user": "admin",
          "connection.password": "password"
          }' \
     http://localhost:8083/connectors/http-sink-2/config | jq .

sleep 4

curl localhost:8083/connectors/http-sink-2/status | jq

# FIXTHIS:
# {
#   "name": "http-sink-2",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "FAILED",
#       "worker_id": "connect:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:206)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:132)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:501)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:478)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:328)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: org.apache.kafka.connect.errors.DataException: Did not find matching union field for data: ANONYMOUS\n\tat io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1466)\n\tat io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1226)\n\tat io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1484)\n\tat io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1226)\n\tat io.confluent.connect.avro.AvroData.toConnectData(AvroData.java:1222)\n\tat io.confluent.connect.avro.AvroConverter.toConnectData(AvroConverter.java:115)\n\tat org.apache.kafka.connect.storage.Converter.toConnectData(Converter.java:87)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.convertValue(WorkerSinkTask.java:545)\n\tat org.apache.kafka.connect.runtime.WorkerSinkTask.lambda$convertAndTransformRecord$1(WorkerSinkTask.java:501)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:156)\n\tat org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:190)\n\t... 13 more\n"
#     }
#   ],
#   "type": "sink"
# }

log "Send userType as null to topic myavrotopic3"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic3 --property value.schema='{"type":"record","name":"EnumStringUnion","namespace":"com.connect.avro","fields":[{"name":"userType","type":["null","string",{"type":"enum","name":"UserType","symbols":["ANONYMOUS","REGISTERED"]}],"default":null}]}' << EOF
{"userType":null}
EOF

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "myavrotopic3",
          "tasks.max": "1",
          "connector.class": "io.confluent.connect.http.HttpSinkConnector",
          "key.converter": "org.apache.kafka.connect.storage.StringConverter",
          "value.converter": "io.confluent.connect.avro.AvroConverter",
          "value.converter.schema.registry.url": "http://schema-registry:8081",
          "value.converter.enhanced.avro.schema.support": "true",
          "confluent.topic.bootstrap.servers": "broker:9092",
          "confluent.topic.replication.factor": "1",
          "reporter.bootstrap.servers": "broker:9092",
          "reporter.error.topic.name": "error-responses",
          "reporter.error.topic.replication.factor": 1,
          "reporter.result.topic.name": "success-responses",
          "reporter.result.topic.replication.factor": 1,
          "http.api.url": "http://http-service-basic-auth:8080/api/messages",
          "request.body.format": "json",
          "auth.type": "BASIC",
          "connection.user": "admin",
          "connection.password": "password"
          }' \
     http://localhost:8083/connectors/http-sink-3/config | jq .

sleep 4

curl localhost:8083/connectors/http-sink-3/status | jq
