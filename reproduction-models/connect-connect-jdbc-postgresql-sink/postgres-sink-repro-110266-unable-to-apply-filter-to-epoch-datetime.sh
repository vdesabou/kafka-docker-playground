#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-110266-unable-to-apply-filter-to-epoch-datetime.yml"

log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
               "topics": "orders_topic",
               "auto.create": "true",

               "transforms": "T1,dateFilter,T2",
               "transforms.dateFilter.type": "io.confluent.connect.transforms.Filter$Value",
               "transforms.dateFilter.filter.type": "exclude",
               "transforms.dateFilter.filter.condition": "$[?(@.tsm < 1592300893000)]",

               "transforms.T1.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
               "transforms.T1.target.type": "unix",
               "transforms.T1.field": "tsm",

               "transforms.T2.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
               "transforms.T2.target.type": "Timestamp",
               "transforms.T2.field": "tsm"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .


log "Sending messages to topic orders_topic (it is filtered as tsm < 1592300893000"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders_topic --property value.schema='{"fields":[{"type":"int","name":"id"},{"type":"string","name":"product"},{"type":"int","name":"quantity"},{"type":"float","name":"price"},{"type":{"logicalType": "timestamp-millis","type": "long"},"name":"tsm"}],"type":"record","name":"myrecord"}' << EOF
{"id": 1, "product": "filtered", "quantity": 100, "price": 50, "tsm": 1583471561000}
EOF

log "Sending messages to topic orders_topic (it is not filtered as tsm > 1592300893000"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders_topic --property value.schema='{"fields":[{"type":"int","name":"id"},{"type":"string","name":"product"},{"type":"int","name":"quantity"},{"type":"float","name":"price"},{"type":{"logicalType": "timestamp-millis","type": "long"},"name":"tsm"}],"type":"record","name":"myrecord"}' << EOF
{"id": 2, "product": "not filtered", "quantity": 100, "price": 50, "tsm": 1592300993000}
EOF

# [2022-06-17 12:57:09,230] ERROR [postgres-sink|task-0] WorkerSinkTask{id=postgres-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.TransformationChain.transformRecord(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.TransformationChain.apply(TransformationChain.java:50)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertAndTransformRecord(WorkerSinkTask.java:543)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.convertMessages(WorkerSinkTask.java:494)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:333)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.jayway.jsonpath.JsonPathException: Could not convert class java.util.Date:Fri Mar 06 05:12:41 GMT 2020 to a ValueNode
#         at com.jayway.jsonpath.internal.filter.ValueNodes$PathNode.evaluate(ValueNodes.java:705)
#         at com.jayway.jsonpath.internal.filter.RelationalExpressionNode.apply(RelationalExpressionNode.java:37)
#         at com.jayway.jsonpath.internal.filter.FilterCompiler$CompiledFilter.apply(FilterCompiler.java:430)
#         at com.jayway.jsonpath.internal.path.PredicatePathToken.accept(PredicatePathToken.java:77)
#         at com.jayway.jsonpath.internal.path.PredicatePathToken.evaluate(PredicatePathToken.java:47)
#         at com.jayway.jsonpath.internal.path.RootPathToken.evaluate(RootPathToken.java:62)
#         at com.jayway.jsonpath.internal.path.CompiledPath.evaluate(CompiledPath.java:99)
#         at com.jayway.jsonpath.internal.path.CompiledPath.evaluate(CompiledPath.java:107)
#         at com.jayway.jsonpath.JsonPath.read(JsonPath.java:185)
#         at io.confluent.connect.transforms.Filter.shouldDrop(Filter.java:225)
#         at io.confluent.connect.transforms.Filter.apply(Filter.java:161)
#         at org.apache.kafka.connect.runtime.TransformationChain.lambda$transformRecord$0(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 15 more
sleep 5

log "Show content of orders_topic table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM orders_topic'" > /tmp/result.log  2>&1
cat /tmp/result.log