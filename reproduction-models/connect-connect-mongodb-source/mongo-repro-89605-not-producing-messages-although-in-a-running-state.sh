#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-89605-not-producing-messages-although-in-a-running-state.yml"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/com.mongodb.kafka.connect \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

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

# https://docs.mongodb.com/kafka-connector/current/troubleshooting/recover-from-invalid-resume-token/#std-label-invalid-resume-token-cause
# no more messages in topic __mongodb_heartbeats due to filter smt
log "Creating MongoDB source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.mongodb.kafka.connect.MongoSourceConnector",
                    "tasks.max" : "1",
                    "connection.uri" : "mongodb://myuser:mypassword@mongodb:27017",
                    "database":"inventory",
                    "collection":"customers",
                    "topic.prefix":"mongo",
                    "offset.partition.name": "my-offset-partition-name-smt",
                    "heartbeat.interval.ms": "3000",
                    "predicates": "isHeartbeat",
                    "predicates.isHeartbeat.pattern": "__mongodb_heartbeats",
                    "predicates.isHeartbeat.type": "org.apache.kafka.connect.transforms.predicates.TopicNameMatches",
                    "transforms": "documentKeyToKey,flattenKey,extractIdKey",
                    "transforms.documentKeyToKey.fields": "documentKey",
                    "transforms.documentKeyToKey.type": "org.apache.kafka.connect.transforms.ValueToKey",
                    "transforms.documentKeyToKey.predicate": "isHeartbeat",
                    "transforms.documentKeyToKey.negate": "true",
                    "transforms.flattenKey.delimiter": ".",
                    "transforms.flattenKey.type": "org.apache.kafka.connect.transforms.Flatten$Key",
                    "transforms.flattenKey.predicate": "isHeartbeat",
                    "transforms.flattenKey.negate": "true",
                    "transforms.extractIdKey.field": "documentKey._id",
                    "transforms.extractIdKey.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
                    "transforms.extractIdKey.predicate": "isHeartbeat",
                    "transforms.extractIdKey.negate": "true",
                    "output.format.key": "schema",
                    "output.format.value": "schema",
                    "output.schema.infer.key": "true"
          }' \
     http://localhost:8083/connectors/mongodb-source-smt2/config | jq .

sleep 5


# [2022-02-14 08:37:05,366] ERROR [mongodb-source-smt|task-0] WorkerSourceTask{id=mongodb-source-smt-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:220)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execute(RetryWithToleranceOperator.java:142)
#         at org.apache.kafka.connect.runtime.TransformationChain.transformRecord(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.TransformationChain.apply(TransformationChain.java:50)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.sendRecords(WorkerSourceTask.java:358)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:272)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.IllegalArgumentException: Unknown field: documentKey._id
#         at org.apache.kafka.connect.transforms.ExtractField.apply(ExtractField.java:65)
#         at org.apache.kafka.connect.runtime.TransformationChain.lambda$transformRecord$0(TransformationChain.java:70)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndRetry(RetryWithToleranceOperator.java:166)
#         at org.apache.kafka.connect.runtime.errors.RetryWithToleranceOperator.execAndHandleError(RetryWithToleranceOperator.java:200)
#         ... 12 more

log "Insert a record"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.insert([
{ _id : 1, first_name : 'Bob', last_name : 'Hopper', email : 'thebob@example.com' }
]);
EOF

log "View record"
docker exec -i mongodb mongosh << EOF
use inventory
db.customers.find().pretty();
EOF

sleep 5

log "Verifying topic mongo.inventory.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mongo.inventory.customers --from-beginning --max-messages 1

log "Checking connect-offsets"
docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true

# we only have 
# ["mongodb-source-smt",{"ns":"my-offset-partition-name-smt"}]    {"_id":"{\"_data\": \"8262064696000000022B022C0100296E5A10045D5F9A1A4CD64D37BECEDF674B8F3991461E5F6964002B020004\", \"_typeBits\": {\"$binary\": {\"base64\": \"QA==\", \"subType\": \"00\"}}}"}
