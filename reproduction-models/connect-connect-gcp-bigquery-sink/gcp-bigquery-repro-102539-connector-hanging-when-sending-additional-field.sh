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

DATASET=pgds102539
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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-102539-connector-hanging-when-sending-additional-field.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "mytable2",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "false",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10001",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",

               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "allowSchemaUnionization": "false",
               "upsertEnabled": "false",
               "deleteEnabled": "false",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .

log "Sending messages to topic mytable2"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic mytable2 --property parse.key=true --property key.separator=, << EOF
"1",{"f1":"value1"}
EOF

log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.mytable2 WHERE DATE(_PARTITIONTIME) = \"2022-04-22\";" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log


curl --request PUT \
  --url http://localhost:8083/admin/loggers/com.wepay.kafka.connect.bigquery \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
 "level": "TRACE"
}'

log "Sending messages to topic mytable2"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic mytable2 --property parse.key=true --property key.separator=, << EOF
"1",{"f1":"value1","f2":"value2"}
EOF


# [2022-04-22 09:33:15,698] DEBUG [gcp-bigquery-sink|task-0] Putting 1 records in the sink. (com.wepay.kafka.connect.bigquery.BigQuerySinkTask:238)
# [2022-04-22 09:33:15,699] DEBUG [gcp-bigquery-sink|task-0] writing 1 row to table GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgds102539, tableId=mytable2$20220422}} (com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter:101)
# [2022-04-22 09:33:15,910] WARN [gcp-bigquery-sink|task-0] You may want to enable schema updates by specifying allowNewBigQueryFields=true or allowBigQueryRequiredFieldRelaxation=true in the properties file (com.wepay.kafka.connect.bigquery.write.row.SimpleBigQueryWriter:69)
# [2022-04-22 09:33:15,910] DEBUG [gcp-bigquery-sink|task-0] A write thread has failed with an unrecoverable error (com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor:67)
# com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:125)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Exception in thread "pool-8-thread-6" com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:125)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)