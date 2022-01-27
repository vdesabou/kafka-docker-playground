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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-90057-jsonparseexception.yml"

log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "a-topic",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "key.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "key.converter.schemas.enable": "false",
               "errors.log.enable": "true",
               "allowSchemaUnionization": "true",
               "upsertEnabled": "false",
               "sanitizeTopics": "true",
               "errors.log.include.messages": "true",
               "errors.deadletterqueue.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "Sending messages to topic a-topic"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
"23283960770403",{"k1Epoch":1642688333164,"acctNo":"23283960","appGrp":"AG1","odLimitAmt":0,"timestamp":"2022-01-14T10:39:00.420807000+00:00","postTxnAvBal":53322.33,"avBalTimestamp":"2022-01-14T10:39:00.420807000+00:00","enablerEventVer":"1.0.0","brand":"LLOYDS","txnDt":"20220104","rmngOdAmt":0,"sortCd":"770403","k2Epoch":1642688333519,"trueRunBal":53322.33,"clrdBalWthdrwl":53322.33,"seqNo":"1156766207961216682","eventCatgry":"CBS-BALANCE-CHG","srcKafkaTopic":"SIT3_KAFKA_CBS_AG1","crncyCd":"GBP","eventTyp":"FP-NEW"}
EOF


log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.a_topic;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

# [2022-01-27 14:22:28,459] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: Index 0 out of bounds for length 0
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.lambda$maybeThrowEncounteredError$0(KCBQThreadPoolExecutor.java:101)
#         at java.base/java.util.Optional.ifPresent(Optional.java:183)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredError(KCBQThreadPoolExecutor.java:100)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:236)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: java.lang.IndexOutOfBoundsException: Index 0 out of bounds for length 0
#         at java.base/jdk.internal.util.Preconditions.outOfBounds(Preconditions.java:64)
#         at java.base/jdk.internal.util.Preconditions.outOfBoundsCheckIndex(Preconditions.java:70)
#         at java.base/jdk.internal.util.Preconditions.checkIndex(Preconditions.java:248)
#         at java.base/java.util.Objects.checkIndex(Objects.java:372)
#         at java.base/java.util.ArrayList.get(ArrayList.java:459)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getUnionizedSchema(SchemaManager.java:372)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getAndValidateProposedSchema(SchemaManager.java:300)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getTableInfo(SchemaManager.java:286)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createTable(SchemaManager.java:232)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptTableCreate(AdaptiveBigQueryWriter.java:161)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:102)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:112)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         ... 3 more