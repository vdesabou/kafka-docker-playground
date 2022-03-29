#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG}
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"


for component in producer-repro-99159
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-99159-illegalargumentexception.yml"

log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_avro",
               "sanitizeTopics" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "batch.size": 1,

               "autoCreateTables": "true",

               "bigQueryPartitionDecorator": "false",

               "allowNewBigQueryFields": "true",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-99159 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

log "Sleeping 125 seconds"
sleep 125

# [2022-03-29 19:19:02,825] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Commit of offsets threw an unexpected exception for sequence number 1: null (org.apache.kafka.connect.runtime.WorkerSinkTask:270)
# com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Some write threads encountered unrecoverable errors: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException, com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException; See logs for more detail
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredErrors(KCBQThreadPoolExecutor.java:108)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.awaitCurrentTasks(KCBQThreadPoolExecutor.java:96)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.flush(BigQuerySinkTask.java:160)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.preCommit(BigQuerySinkTask.java:176)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:405)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:673)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:668)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-03-29 19:19:02,825] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Some write threads encountered unrecoverable errors: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException, com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write to table
# Caused by: java.lang.IllegalArgumentException; See logs for more detail
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredErrors(KCBQThreadPoolExecutor.java:108)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:233)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.kcbq_quickstart1;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

log "Drop dataset $DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

docker rm -f gcloud-config