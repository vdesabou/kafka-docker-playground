#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


file="producer-repro-99762-customer.proto"
cd producer-repro-99762/src/main/resources/
get_3rdparty_file "$file"
if [ ! -f $file ]
then
     logerror "ERROR: $file is missing"
     exit 1
else
     mv $file Customer.proto
fi
cd -

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



for component in producer-repro-99762
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-99762-recursion-with-protobuf.yml"

if version_gt $CONNECTOR_TAG "1.9.9"
then
     log "Creating GCP BigQuery Sink connector"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "customer_protobuf",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "defaultDataset" : "'"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json",

"value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
"value.converter.schema.registry.url": "http://schema-registry:8081"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
else
     log "Creating GCP BigQuery Sink connector"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "customer_protobuf",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "autoUpdateSchemas" : "true",
                    "schemaRetriever" : "com.wepay.kafka.connect.bigquery.schemaregistry.schemaretriever.SchemaRegistrySchemaRetriever",
                    "schemaRegistryLocation": "http://schema-registry:8081",
                    "datasets" : ".*='"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
fi

log "✨ Run the protobuf java producer which produces to topic customer_protobuf"
docker exec producer-repro-99762 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

log "Sleeping 125 seconds"
sleep 125


# [2022-04-04 15:21:33,971] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: A write thread has failed with an unrecoverable error
# Caused by: Kafka Connect schema contains cycle
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.lambda$maybeThrowEncounteredError$0(KCBQThreadPoolExecutor.java:101)
#         at java.base/java.util.Optional.ifPresent(Optional.java:183)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredError(KCBQThreadPoolExecutor.java:100)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:236)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: com.wepay.kafka.connect.bigquery.exception.ConversionConnectException: Kafka Connect schema contains cycle
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:136)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:149)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:149)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:142)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:149)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at java.base/java.util.Collections$UnmodifiableCollection.forEach(Collections.java:1085)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:149)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:142)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:149)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at java.base/java.util.Collections$UnmodifiableCollection.forEach(Collections.java:1085)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:149)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:149)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at java.base/java.util.Collections$UnmodifiableCollection.forEach(Collections.java:1085)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:149)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.lambda$throwOnCycle$1(BigQuerySchemaConverter.java:149)
#         at java.base/java.util.ArrayList.forEach(ArrayList.java:1541)
#         at java.base/java.util.Collections$UnmodifiableCollection.forEach(Collections.java:1085)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.throwOnCycle(BigQuerySchemaConverter.java:149)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertSchema(BigQuerySchemaConverter.java:116)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertSchema(BigQuerySchemaConverter.java:46)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getBigQuerySchema(SchemaManager.java:609)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.convertRecordSchema(SchemaManager.java:370)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getAndValidateProposedSchema(SchemaManager.java:320)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getTableInfo(SchemaManager.java:294)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createTable(SchemaManager.java:240)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptTableCreate(AdaptiveBigQueryWriter.java:161)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:102)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:112)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         ... 3 more

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_protobuf;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

log "Drop dataset $DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

docker rm -f gcloud-config