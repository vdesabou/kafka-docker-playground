#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-87791
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

DATASET=pgrepro
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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-87791.yml"

log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer-avro",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "deleteEnabled": "true",
               "autoCreateTables" : "true",
               "kafkaKeyFieldName": "KEY",
               "intermediateTableSuffix": "_intermediate",
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url" : "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .

log "Run the Java producer-87791"
docker exec producer-87791 bash -c "java -jar producer-87791-1.0.0-jar-with-dependencies.jar"

log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "MODIFIEDDATE" /tmp/result.log

# [2022-01-11 14:28:30,923] ERROR [gcp-bigquery-sink|task-0] Task failed with com.google.cloud.bigquery.BigQueryException error: Syntax error: Unexpected keyword EXCLUDE at [1:847] (com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor:70)
# Exception in thread "pool-4-thread-4" com.google.cloud.bigquery.BigQueryException: Syntax error: Unexpected keyword EXCLUDE at [1:847]
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.translate(HttpBigQueryRpc.java:113)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.getQueryResults(HttpBigQueryRpc.java:623)
#         at com.google.cloud.bigquery.BigQueryImpl$34.call(BigQueryImpl.java:1222)
#         at com.google.cloud.bigquery.BigQueryImpl$34.call(BigQueryImpl.java:1217)
#         at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
#         at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
#         at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
#         at com.google.cloud.bigquery.BigQueryImpl.getQueryResults(BigQueryImpl.java:1216)
#         at com.google.cloud.bigquery.BigQueryImpl.getQueryResults(BigQueryImpl.java:1200)
#         at com.google.cloud.bigquery.Job$1.call(Job.java:332)
#         at com.google.cloud.bigquery.Job$1.call(Job.java:329)
#         at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
#         at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
#         at com.google.cloud.RetryHelper.poll(RetryHelper.java:64)
#         at com.google.cloud.bigquery.Job.waitForQueryResults(Job.java:328)
#         at com.google.cloud.bigquery.Job.getQueryResults(Job.java:291)
#         at com.google.cloud.bigquery.BigQueryImpl.query(BigQueryImpl.java:1187)
#         at com.wepay.kafka.connect.bigquery.MergeQueries.mergeFlush(MergeQueries.java:137)
#         at com.wepay.kafka.connect.bigquery.MergeQueries.lambda$mergeFlush$1(MergeQueries.java:119)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.api.client.googleapis.json.GoogleJsonResponseException: 400 Bad Request
# GET https://www.googleapis.com/bigquery/v2/projects/vincent-de-saboulin-lab/queries/25e758df-4847-4b7c-97a6-d270698132f3?location=US&maxResults=0&prettyPrint=false
# {
#   "code" : 400,
#   "errors" : [ {
#     "domain" : "global",
#     "location" : "q",
#     "locationType" : "parameter",
#     "message" : "Syntax error: Unexpected keyword EXCLUDE at [1:847]",
#     "reason" : "invalidQuery"
#   } ],
#   "message" : "Syntax error: Unexpected keyword EXCLUDE at [1:847]",
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
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.getQueryResults(HttpBigQueryRpc.java:621)
#         ... 20 more