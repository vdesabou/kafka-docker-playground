#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "5.9.0"; then
     log "Hbase does not support JDK 11, see https://hbase.apache.org/book.html#java"
     # known_issue https://github.com/vdesabou/kafka-docker-playground/issues/907
     exit 107
fi

PROJECT=${1:-vincent-de-saboulin-lab}
INSTANCE=${2:-test-instance}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90211-check-if-schema-is-required.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Deleting instance, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $INSTANCE --project $PROJECT  << EOF
Y
EOF
set -e
log "Create a BigTable Instance and Database"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances create $INSTANCE --project $PROJECT --cluster $INSTANCE --cluster-zone=us-east1-c --display-name="playground-bigtable-instance" --instance-type=DEVELOPMENT

log "Sending messages to topic stats"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic stats --property parse.key=true --property key.separator=, << EOF
"simple-key-1", {"users": {"name":"Bob","friends": "1000"}}
"simple-key-2", {"users": {"name":"Jess","friends": "10000"}}
"simple-key-3", {"users": {"name":"John","friends": "10000"}}
EOF


#  Using JSON with schema (and key): (it works)
# docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
# 1,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record1"}}
# 2,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record2"}}
# 3,{"schema":{"type":"struct","fields":[{"type":"string","optional":false,"field":"record"}]},"payload":{"record":"record3"}}
# EOF



log "Creating GCP BigTbale Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcp.bigtable.BigtableSinkConnector",
               "tasks.max" : "1",
               "topics" : "a-topic",
               "auto.create" : "true",
               "gcp.bigtable.credentials.path": "/tmp/keyfile.json",
               "gcp.bigtable.instance.id": "'"$INSTANCE"'",
               "gcp.bigtable.project.id": "'"$PROJECT"'",
               "auto.create.tables": "true",
               "auto.create.column.families": "true",
               "table.name.format" : "kafka_${topic}",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/gcp-bigtable-sink-a-topic/config | jq .

sleep 30

log "Verify data is in GCP BigTable"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $PROJECT -instance $INSTANCE read kafka_a-topic > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Bob" /tmp/result.log

# [2022-01-28 08:24:24,445] ERROR [gcp-bigtable-sink|task-0] WorkerSinkTask{id=gcp-bigtable-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: null (org.apache.kafka.connect.runtime.WorkerSinkTask:565)
# java.lang.NullPointerException
#         at io.confluent.connect.bigtable.client.BufferedWriter.getColumnValueFromField(BufferedWriter.java:265)
#         at io.confluent.connect.bigtable.client.BufferedWriter.addPrimitiveRecordWriteToBatch(BufferedWriter.java:152)
#         at io.confluent.connect.bigtable.client.BufferedWriter.addWriteToBatch(BufferedWriter.java:88)
#         at io.confluent.connect.bigtable.client.InsertWriter.write(InsertWriter.java:47)
#         at io.confluent.connect.bigtable.BaseBigtableSinkTask.put(BaseBigtableSinkTask.java:100)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:545)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:325)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:228)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:184)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# [2022-01-28 08:24:24,446] ERROR [gcp-bigtable-sink|task-0] WorkerSinkTask{id=gcp-bigtable-sink-0} Task threw an uncaught and unrecoverable exception (org.apache.kafka.connect.runtime.WorkerTask:186)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:567)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:325)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:228)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:184)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:234)
#         at java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:511)
#         at java.util.concurrent.FutureTask.run(FutureTask.java:266)
#         at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1149)
#         at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:624)
#         at java.lang.Thread.run(Thread.java:748)
# Caused by: java.lang.NullPointerException
#         at io.confluent.connect.bigtable.client.BufferedWriter.getColumnValueFromField(BufferedWriter.java:265)
#         at io.confluent.connect.bigtable.client.BufferedWriter.addPrimitiveRecordWriteToBatch(BufferedWriter.java:152)
#         at io.confluent.connect.bigtable.client.BufferedWriter.addWriteToBatch(BufferedWriter.java:88)
#         at io.confluent.connect.bigtable.client.InsertWriter.write(InsertWriter.java:47)
#         at io.confluent.connect.bigtable.BaseBigtableSinkTask.put(BaseBigtableSinkTask.java:100)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:545)
#         ... 10 more

log "Delete table"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $PROJECT -instance $INSTANCE deletetable kafka_stats

log "Deleting instance"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $INSTANCE --project $PROJECT  << EOF
Y
EOF

docker rm -f gcloud-config
