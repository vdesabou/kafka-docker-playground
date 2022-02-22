#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f schema.avsc ]
then
     logerror "schema.avsc is missing"
     exit 1
fi

if [ ! -f message.json ]
then
     logerror "message.json is missing"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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

docker cp schema.avsc connect:/tmp/
docker cp message.json connect:/tmp/
docker exec -i connect bash -c "kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic --property value.schema.file=/tmp/schema.avsc < /tmp/message.json"


if version_gt $CONNECTOR_TAG "1.9.9"
then
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "myavrotopic",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "autoUpdateSchemas" : "true",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.enhanced.avro.schema.support": "false",
                    "defaultDataset" : "'"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "sanitizeFieldNames": "true",
                    "allBQFieldsNullable": "true",
                    "allowBigQueryRequiredFieldRelaxation": "true",
                    "keyfile" : "/tmp/keyfile.json"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
else
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "myavrotopic",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "autoUpdateSchemas" : "true",
                    "schemaRetriever" : "com.wepay.kafka.connect.bigquery.schemaregistry.schemaretriever.SchemaRegistrySchemaRetriever",
                    "schemaRegistryLocation": "http://schema-registry:8081",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.enhanced.avro.schema.support": "false",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "sanitizeFieldNames": "true",
                    "datasets" : ".*='"$DATASET"'",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
fi

# with 1.5.2
# [2021-06-05 16:11:59,252] ERROR WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: The RECORD field must have at least one sub-field (org.apache.kafka.connect.runtime.WorkerSinkTask)
# java.lang.IllegalArgumentException: The RECORD field must have at least one sub-field
#         at com.google.cloud.bigquery.Field$Builder.setType(Field.java:149)
#         at com.google.cloud.bigquery.Field.newBuilder(Field.java:285)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertStruct(BigQuerySchemaConverter.java:175)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertField(BigQuerySchemaConverter.java:127)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertStruct(BigQuerySchemaConverter.java:169)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertField(BigQuerySchemaConverter.java:127)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertStruct(BigQuerySchemaConverter.java:169)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertField(BigQuerySchemaConverter.java:127)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertSchema(BigQuerySchemaConverter.java:109)
#         at com.wepay.kafka.connect.bigquery.convert.BigQuerySchemaConverter.convertSchema(BigQuerySchemaConverter.java:43)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getBigQuerySchema(SchemaManager.java:101)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.constructTableInfo(SchemaManager.java:86)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createTable(SchemaManager.java:67)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.maybeCreateTable(BigQuerySinkTask.java:170)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.getRecordTable(BigQuerySinkTask.java:144)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:207)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:586)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
