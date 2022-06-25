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

file="producer-repro-101365-customer.avsc"
mkdir -p producer-repro-101365/src/main/resources/avro
cd producer-repro-101365/src/main/resources/avro/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file customer.avsc
fi
cd -

file="producer-repro-101365-2-customer.avsc"
mkdir -p producer-repro-101365-2/src/main/resources/avro
cd producer-repro-101365-2/src/main/resources/avro/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file customer.avsc
fi
cd -

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


for component in producer-repro-101365 producer-repro-101365-2
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-101365-allowschemaunionization-is-not-working.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_avro",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",

               "allowSchemaUnionization": "true",
               "sanitizeFieldNames" : "false",
               "upsertEnabled": "false",
               "deleteEnabled": "false",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true",
               "bigQueryPartitionDecorator" : "false",
               "allowNewBigQueryFields": "true",
               "allowBigQueryRequiredFieldRelaxation": "true"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-101365 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"


log "Sleeping 120 seconds"
sleep 120

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log

log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-101365-2 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

# with 2.2.0-rc-dd4f439

# [2022-05-09 12:23:45,900] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Commit of offsets threw an unexpected exception for sequence number 3: null (org.apache.kafka.connect.runtime.WorkerSinkTask:270)
# com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Some write threads encountered unrecoverable errors: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to write rows after BQ table creation or schema update within 30 attempts for: GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgec2userds711, tableId=customer_avro}}; See logs for more detail
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredErrors(KCBQThreadPoolExecutor.java:108)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.awaitCurrentTasks(KCBQThreadPoolExecutor.java:96)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.flush(BigQuerySinkTask.java:160)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.preCommit(BigQuerySinkTask.java:176)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.commitOffsets(WorkerSinkTask.java:405)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closePartitions(WorkerSinkTask.java:653)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.closeAllPartitions(WorkerSinkTask.java:648)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:205)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)