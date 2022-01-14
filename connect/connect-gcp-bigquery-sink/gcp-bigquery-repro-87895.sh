#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-87895 producer-87895-2
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

function wait_for_repro () {
     ERROR="$1"
     MAX_WAIT=600
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for error $ERROR to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep -i "$ERROR" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show '$ERROR' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}


PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

# pgrepro should exist with table created like this: https://github.com/vdesabou/kafka-docker-playground/blob/e8ee3b1cfd8b0704b70a669f147fe16e958ac14e/connect/connect-gcp-bigquery-sink/producer-87895/customer-avro.jpg
DATASET=pgrepro
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-87895.yml"

log "Creating GCP BigQuery Sink connector with autoCreateTables=true"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer-avro",
               "sanitizeFieldNames": "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "deleteEnabled": "true",
               "upsertEnabled": "true",
               "kafkaKeyFieldName": "KEY",
               "intermediateTableSuffix": "_intermediate",
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url" : "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink-key-nullable-to-required/config | jq .


log "Run the Java producer-87895 (KEY is REQUIRED)"
docker exec producer-87895 bash -c "java -jar producer-87895-1.0.0-jar-with-dependencies.jar"

wait_for_repro "Field KEY.KEY has changed mode from NULLABLE to REQUIRED"

# [2022-01-11 16:59:38,234] INFO [gcp-bigquery-sink|task-0] Attempting to update table `pgrepro`.`customer-avro` with schema Schema{fields=[Field{name=count, type=INTEGER, mode=REQUIRED, description=null, policyTags=null}, Field{name=first_name, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=last_name, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=address, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=KEY, type=RECORD, mode=NULLABLE, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:255)
# Exception in thread "pool-6-thread-3" com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to create table GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgrepro, tableId=customer_avro__intermediate_0_a3fe48e9_191e_42bb_88be_2334e52cfe7c_1641920361088}}
# Caused by: Provided Schema does not match Table vincent-de-saboulin-lab:pgrepro.customer-avro. Field KEY.KEY has changed mode from NULLABLE to REQUIRED
# [2022-01-11 16:59:38,686] ERROR [gcp-bigquery-sink|task-0] Task failed with com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException error: Failed to create table GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgrepro, tableId=customer_avro__intermediate_0_a3fe48e9_191e_42bb_88be_2334e52cfe7c_1641920361088}} (com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor:70)
#         at com.wepay.kafka.connect.bigquery.write.row.UpsertDeleteBigQueryWriter.attemptTableCreate(UpsertDeleteBigQueryWriter.java:89)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:115)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:118)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:96)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.cloud.bigquery.BigQueryException: Provided Schema does not match Table vincent-de-saboulin-lab:pgrepro.customer-avro. Field KEY.KEY has changed mode from NULLABLE to REQUIRED
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.translate(HttpBigQueryRpc.java:113)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.patch(HttpBigQueryRpc.java:270)
#         at com.google.cloud.bigquery.BigQueryImpl$14.call(BigQueryImpl.java:590)
#         at com.google.cloud.bigquery.BigQueryImpl$14.call(BigQueryImpl.java:587)
#         at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
#         at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
#         at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
#         at com.google.cloud.bigquery.BigQueryImpl.update(BigQueryImpl.java:586)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.updateSchema(SchemaManager.java:257)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createOrUpdateTable(SchemaManager.java:207)
#         at com.wepay.kafka.connect.bigquery.write.row.UpsertDeleteBigQueryWriter.attemptTableCreate(UpsertDeleteBigQueryWriter.java:87)
#         ... 6 more
# Caused by: com.google.api.client.googleapis.json.GoogleJsonResponseException: 400 Bad Request
# POST https://www.googleapis.com/bigquery/v2/projects/vincent-de-saboulin-lab/datasets/pgrepro/tables/customer-avro?prettyPrint=false
# {
#   "code" : 400,
#   "errors" : [ {
#     "domain" : "global",
#     "message" : "Provided Schema does not match Table vincent-de-saboulin-lab:pgrepro.customer-avro. Field KEY.KEY has changed mode from NULLABLE to REQUIRED",
#     "reason" : "invalid"
#   } ],
#   "message" : "Provided Schema does not match Table vincent-de-saboulin-lab:pgrepro.customer-avro. Field KEY.KEY has changed mode from NULLABLE to REQUIRED",
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
#         ... 15 more

log "Creating GCP BigQuery Sink connector with autoCreateTables=false"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer-avro2",
               "sanitizeFieldNames": "true",
               "autoCreateTables" : "false",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "deleteEnabled": "true",
               "upsertEnabled": "true",
               "kafkaKeyFieldName": "KEY",
               "intermediateTableSuffix": "_intermediate",
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url" : "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink-tombstones/config | jq .


log "Run the Java producer-87895-2 (only composed of tombstones)"
docker exec producer-87895-2 bash -c "java -jar producer-87895-2-1.0.0-jar-with-dependencies.jar"

wait_for_repro "Failed to unionize schemas of records for the table"

