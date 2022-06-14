#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-109617-only-struct-objects-supported-for-field-insertion-found:-java.lang.string.yml"

log "Initialize MongoDB replica set"
docker exec -i mongodb mongo --eval 'rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})'

sleep 5

log "Create a user profile"
docker exec -i mongodb mongosh << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
EOF

sleep 2

# log "Sending messages to topic orders"
# docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic orders --property parse.key=true --property key.separator=, << EOF
# key1,value1
# key1,value2
# key2,value1
# EOF

# log "Creating MongoDB sink connector"
# curl -X PUT \
#      -H "Content-Type: application/json" \
#      --data '{
#                "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
#                     "tasks.max" : "1",
#                     "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",

#                     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
#                     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
#                     "value.converter.schemas.enable": "false",
                    
#                     "database":"inventory",
#                     "collection":"customers",
#                     "topics":"orders",

#                     "transforms": "insert",
#                     "transforms.insert.type": "org.apache.kafka.connect.transforms.InsertField$Value",
#                     "transforms.insert.timestamp.field": "mytimestamp"
#           }' \
#      http://localhost:8083/connectors/mongodb-sink/config | jq .


# [2022-06-14 08:05:01,435] ERROR [mongodb-sink|task-0] WorkerSinkTask{id=mongodb-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
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
# Caused by: org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String
#         at org.apache.kafka.connect.transforms.util.Requirements.requireStruct(Requirements.java:52)
#         at org.apache.kafka.connect.transforms.InsertField.applyWithSchema(InsertField.java:164)
#         at org.apache.kafka.connect.transforms.InsertField.apply(InsertField.java:135)
#         at org.apache.kafka.connect.runtime.TransformationChain.lambda$transformRecord$0(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 15 more


log "Sending messages to topic orders_json"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic orders_json --property parse.key=true --property key.separator=, << EOF
key1,{"test":"ok"}
key1,{"test":"ok2"}
key2,{"test":"ok"}
EOF


log "Creating MongoDB sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSinkConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",

                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false",
                    
                    "database":"inventory",
                    "collection":"customers",
                    "topics":"orders_json",
                    "timeseries.timefield": "mytimestamp",
                    "timeseries.metafield": "vinc",

                    "transforms": "insert",
                    "transforms.insert.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.insert.timestamp.field": "mytimestamp"
          }' \
     http://localhost:8083/connectors/mongodb-sink-json/config | jq .

sleep 10

log "View record"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.find().pretty();
EOF


# [2022-06-14 12:35:34,282] ERROR [mongodb-sink-json|task-0] WorkerSinkTask{id=mongodb-sink-json-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
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
# Caused by: org.apache.kafka.connect.errors.DataException: com.mongodb.MongoBulkWriteException: Bulk write operation error on server mongodb:27017. Write errors: [BulkWriteError{index=0, code=2, message=''mytimestamp' must be present and contain a valid BSON UTC datetime value', details={}}]. 
#         at com.mongodb.kafka.connect.sink.StartedMongoSinkTask.handleTolerableWriteException(StartedMongoSinkTask.java:168)
#         at com.mongodb.kafka.connect.sink.StartedMongoSinkTask.bulkWriteBatch(StartedMongoSinkTask.java:111)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at com.mongodb.kafka.connect.sink.StartedMongoSinkTask.put(StartedMongoSinkTask.java:76)
#         at com.mongodb.kafka.connect.sink.MongoSinkTask.put(MongoSinkTask.java:90)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more
# Caused by: com.mongodb.MongoBulkWriteException: Bulk write operation error on server mongodb:27017. Write errors: [BulkWriteError{index=0, code=2, message=''mytimestamp' must be present and contain a valid BSON UTC datetime value', details={}}]. 
#         at com.mongodb.internal.connection.BulkWriteBatchCombiner.getError(BulkWriteBatchCombiner.java:167)
#         at com.mongodb.internal.connection.BulkWriteBatchCombiner.throwOnError(BulkWriteBatchCombiner.java:192)
#         at com.mongodb.internal.connection.BulkWriteBatchCombiner.getResult(BulkWriteBatchCombiner.java:136)
#         at com.mongodb.internal.operation.BulkWriteBatch.getResult(BulkWriteBatch.java:224)
#         at com.mongodb.internal.operation.MixedBulkWriteOperation.executeBulkWriteBatch(MixedBulkWriteOperation.java:363)
#         at com.mongodb.internal.operation.MixedBulkWriteOperation.lambda$execute$2(MixedBulkWriteOperation.java:260)
#         at com.mongodb.internal.operation.OperationHelper.lambda$withSourceAndConnection$2(OperationHelper.java:575)
#         at com.mongodb.internal.operation.OperationHelper.withSuppliedResource(OperationHelper.java:600)
#         at com.mongodb.internal.operation.OperationHelper.lambda$withSourceAndConnection$3(OperationHelper.java:574)
#         at com.mongodb.internal.operation.OperationHelper.withSuppliedResource(OperationHelper.java:600)
#         at com.mongodb.internal.operation.OperationHelper.withSourceAndConnection(OperationHelper.java:573)
#         at com.mongodb.internal.operation.MixedBulkWriteOperation.lambda$execute$3(MixedBulkWriteOperation.java:232)
#         at com.mongodb.internal.async.function.RetryingSyncSupplier.get(RetryingSyncSupplier.java:65)
#         at com.mongodb.internal.operation.MixedBulkWriteOperation.execute(MixedBulkWriteOperation.java:268)
#         at com.mongodb.internal.operation.MixedBulkWriteOperation.execute(MixedBulkWriteOperation.java:84)
#         at com.mongodb.client.internal.MongoClientDelegate$DelegateOperationExecutor.execute(MongoClientDelegate.java:212)
#         at com.mongodb.client.internal.MongoCollectionImpl.executeBulkWrite(MongoCollectionImpl.java:443)
#         at com.mongodb.client.internal.MongoCollectionImpl.bulkWrite(MongoCollectionImpl.java:423)
#         at com.mongodb.kafka.connect.sink.StartedMongoSinkTask.bulkWriteBatch(StartedMongoSinkTask.java:104)
#         ... 14 more

# [
#   {
#     _id: ObjectId("62a84231885d270b8092b0f9"),
#     test: 'ok',
#     mytimestamp: Long("1655194150126")
#   },
#   {
#     _id: ObjectId("62a84231885d270b8092b0fa"),
#     test: 'ok2',
#     mytimestamp: Long("1655194150145")
#   },
#   {
#     _id: ObjectId("62a84231885d270b8092b0fb"),
#     test: 'ok',
#     mytimestamp: Long("1655194150145")
#   }
# ]