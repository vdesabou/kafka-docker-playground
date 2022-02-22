#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

# {
#     "fields": [
#         {
#             "default": null,
#             "name": "UnionField",
#             "type": [
#                 "null",
#                 {
#                     "fields": [
#                         {
#                             "default": false,
#                             "name": "InnerField",
#                             "type": [
#                                 "boolean",
#                                 "null"
#                             ]
#                         }
#                     ],
#                     "name": "InnerStruct",
#                     "type": "record"
#                 },
#                 {
#                     "fields": [
#                         {
#                             "default": false,
#                             "name": "InnerField",
#                             "type": [
#                                 "boolean",
#                                 "null"
#                             ]
#                         }
#                     ],
#                     "name": "InnerStruct2",
#                     "type": "record"
#                 }
#             ]
#         }
#     ],
#     "name": "OuterStruct",
#     "namespace": "com.example",
#     "type": "record"
# }

log "Send message"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic myavrotopic1 --property value.schema='{"fields":[{"default":null,"type":["null",{"fields":[{"default":false,"type":["boolean","null"],"name":"InnerField"}],"type":"record","name":"InnerStruct"},{"fields":[{"default":false,"type":["boolean","null"],"name":"InnerField"}],"type":"record","name":"InnerStruct2"}],"name":"UnionField"}],"namespace":"com.example","name":"OuterStruct","type":"record"}' << EOF
{"UnionField":{"com.example.InnerStruct":{"InnerField": { "boolean": true}}}}
EOF

log "Creating GCP BigQuery Sink connector gcp-bigquery-sink-1 with value.converter.enhanced.avro.schema.support=true, in order to avoid the issue, do not set it or set it to false !"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "myavrotopic1",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "autoUpdateSchemas" : "true",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.enhanced.avro.schema.support": "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "sanitizeFieldNames": "true",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink-1/config | jq .

sleep 4

curl localhost:8083/connectors/gcp-bigquery-sink-1/status | jq

# [2021-06-05 15:18:30,395] ERROR Task failed with com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException error: Failed to create table GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgvsaboulinds611, tableId=myavrotopic44}} (com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor)
# Exception in thread "pool-7-thread-1" com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to create table GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgvsaboulinds611, tableId=myavrotopic44}}
# Caused by: Invalid field name "com.example.InnerStruct". Fields must contain only letters, numbers, and underscores, start with a letter or underscore, and be at most 300 characters long.
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptTableCreate(AdaptiveBigQueryWriter.java:170)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:115)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:118)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:96)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.cloud.bigquery.BigQueryException: Invalid field name "com.example.InnerStruct". Fields must contain only letters, numbers, and underscores, start with a letter or underscore, and be at most 300 characters long.
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.translate(HttpBigQueryRpc.java:113)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.create(HttpBigQueryRpc.java:186)
#         at com.google.cloud.bigquery.BigQueryImpl$2.call(BigQueryImpl.java:253)
#         at com.google.cloud.bigquery.BigQueryImpl$2.call(BigQueryImpl.java:250)
#         at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
#         at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
#         at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
#         at com.google.cloud.bigquery.BigQueryImpl.create(BigQueryImpl.java:249)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createTable(SchemaManager.java:229)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptTableCreate(AdaptiveBigQueryWriter.java:168)
#         ... 6 more
# Caused by: com.google.api.client.googleapis.json.GoogleJsonResponseException: 400 Bad Request
# POST https://www.googleapis.com/bigquery/v2/projects/vincent-de-saboulin-lab/datasets/pgvsaboulinds611/tables?prettyPrint=false
# {
#   "code" : 400,
#   "errors" : [ {
#     "domain" : "global",
#     "message" : "Invalid field name \"com.example.InnerStruct\". Fields must contain only letters, numbers, and underscores, start with a letter or underscore, and be at most 300 characters long.",
#     "reason" : "invalid"
#   } ],
#   "message" : "Invalid field name \"com.example.InnerStruct\". Fields must contain only letters, numbers, and underscores, start with a letter or underscore, and be at most 300 characters long.",
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
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.create(HttpBigQueryRpc.java:184)
#         ... 14 more