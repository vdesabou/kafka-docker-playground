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

DATASET=pgvinc-88043
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "my_topic",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "allowBigQueryRequiredFieldRelaxation": "true",
               "allowNewBigQueryFields" : "true",
               "allowSchemaUnionization" : "false",
               "allBQFieldsNullable" : "false",
               "deleteEnabled": "false",
               "upsertEnabled": "false",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "errors.tolerance" : "all",
               "errors.log.enable" : "true",
               "errors.log.include.messages" : "true",
               "errors.deadletterqueue.topic.name" : "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable" : "true"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "Sending messages to topic my_topic which can be null"
seq -f "{\"f1\": {\"string\": \"value%g-`date`\"}}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"fields":[{"default":null,"type":["null","string"],"name":"f1"}],"type":"record","name":"myrecord"}'

log "Sending one records with f1 null"
echo "{\"f1\": null}" | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"fields":[{"default":null,"type":["null","string"],"name":"f1"}],"type":"record","name":"myrecord"}'

log "Sleeping 30 seconds"
sleep 30

log "Change compatibility mode to NONE"
curl --request PUT \
  --url http://localhost:8081/config \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "compatibility": "NONE"
}'

seq -f "{\"f1\": {\"string\": \"value%g-`date`\"}}" 10000 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"fields":[{"default":null,"type":["null","string"],"name":"f1"}],"type":"record","name":"myrecord"}'

log "Changing schema: f1 changed to required and adding f2 (also required)"
curl --request POST \
  --url http://localhost:8081/subjects/my_topic-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"f2\",\"type\":\"string\"}]}"
}'

log "Sending messages to topic my_topic which cannot be null (f1 changed to required) and adding a field f2"
seq -f "{\"f1\": \"value%g-`date`\",\"f2\": \"value\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"},{"name":"f2","type":"string"}]}'

# log "Verify data is in GCP BigQuery:"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.my_topic;" > /tmp/result.log  2>&1
# cat /tmp/result.log

# [2022-01-26 13:12:05,958] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: Failed to update table schema for: GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgvinc88043, tableId=my_topic}}
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.lambda$maybeThrowEncounteredError$0(KCBQThreadPoolExecutor.java:101)
#         at java.base/java.util.Optional.ifPresent(Optional.java:183)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredError(KCBQThreadPoolExecutor.java:100)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:236)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to update table schema for: GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgvinc88043, tableId=my_topic}}
# Caused by: Provided Schema does not match Table vincent-de-saboulin-lab:pgvinc88043.my_topic. Field f1 has changed mode from NULLABLE to REQUIRED
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptSchemaUpdate(AdaptiveBigQueryWriter.java:155)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:97)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:112)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         ... 3 more
# Caused by: com.google.cloud.bigquery.BigQueryException: Provided Schema does not match Table vincent-de-saboulin-lab:pgvinc88043.my_topic. Field f1 has changed mode from NULLABLE to REQUIRED
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.translate(HttpBigQueryRpc.java:113)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.patch(HttpBigQueryRpc.java:270)
#         at com.google.cloud.bigquery.BigQueryImpl$14.call(BigQueryImpl.java:590)
#         at com.google.cloud.bigquery.BigQueryImpl$14.call(BigQueryImpl.java:587)
#         at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
#         at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
#         at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
#         at com.google.cloud.bigquery.BigQueryImpl.update(BigQueryImpl.java:586)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.updateSchema(SchemaManager.java:266)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptSchemaUpdate(AdaptiveBigQueryWriter.java:152)
#         ... 6 more
# Caused by: com.google.api.client.googleapis.json.GoogleJsonResponseException: 400 Bad Request
# POST https://www.googleapis.com/bigquery/v2/projects/vincent-de-saboulin-lab/datasets/pgvinc88043/tables/my_topic?prettyPrint=false
# {
#   "code" : 400,
#   "errors" : [ {
#     "domain" : "global",
#     "message" : "Provided Schema does not match Table vincent-de-saboulin-lab:pgvinc88043.my_topic. Field f1 has changed mode from NULLABLE to REQUIRED",
#     "reason" : "invalid"
#   } ],
#   "message" : "Provided Schema does not match Table vincent-de-saboulin-lab:pgvinc88043.my_topic. Field f1 has changed mode from NULLABLE to REQUIRED",
#   "status" : "INVALID_ARGUMENT"
# }
#         at com.google.api.client.googleapis.json.GoogleJsonResponseException.from(GoogleJsonResponseException.java:149)
#         at com.google.api.client.googleapis.services.json.AbstractGoogleJsonClientRequest.newExceptionOnError(AbstractGoogleJsonClientRequest.java:112)
#         at com.google.api.client.googleapis.services.json.AbstractGoogleJsonClientRequest.newExceptionOnError(AbstractGoogleJsonClientRequest.java:39)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest$1.interceptResponse(AbstractGoogleClientRequest.java:443)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1108)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.executeUnparsed(AbstractGoogleClientRequest.java:541)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.executeUnparsed(AbstractGoogleClientRequest.java:474)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.execute(AbstractGoogleClientRequest.java:591)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.patch(HttpBigQueryRpc.java:268)
#         ... 14 more

sleep 30

while [ true ]
do
     log "Restart failed tasks"
     curl --request POST --url 'http://localhost:8083/connectors/gcp-bigquery-sink/restart?includeTasks=true&onlyFailed=false'
     sleep 2
done
