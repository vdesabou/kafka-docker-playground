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

# log "Doing gsutil authentication"
# set +e
# docker rm -f gcloud-config
# set -e
# docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

# set +e
# log "Drop dataset $DATASET, this might fail"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
# set -e

# log "Create dataset $PROJECT.$DATASET"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-102539-connector-hanging-when-sending-additional-field.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "mytable2",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
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

#"autoCreateTables" : "true"
# [2022-04-22 09:48:31,368] DEBUG [gcp-bigquery-sink|task-0] Putting 0 records in the sink. (com.wepay.kafka.connect.bigquery.BigQuerySinkTask:238)
# [2022-04-22 09:48:35,866] TRACE [gcp-bigquery-sink|task-0] insertion failed (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:114)
# [2022-04-22 09:48:35,867] TRACE [gcp-bigquery-sink|task-0] write response contained errors: 
# {0=[BigQueryError{reason=invalid, location=f2, message=no such field: f2.}]} (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:178)
# [2022-04-22 09:48:35,867] DEBUG [gcp-bigquery-sink|task-0] re-attempting insertion (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:119)
# [2022-04-22 09:49:06,073] TRACE [gcp-bigquery-sink|task-0] insertion failed (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:114)
# [2022-04-22 09:49:06,073] TRACE [gcp-bigquery-sink|task-0] write response contained errors: 
# {0=[BigQueryError{reason=invalid, location=f2, message=no such field: f2.}]} (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:178)
# [2022-04-22 09:49:06,073] DEBUG [gcp-bigquery-sink|task-0] re-attempting insertion (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:119)
# [2022-04-22 09:49:36,276] TRACE [gcp-bigquery-sink|task-0] insertion failed (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:114)
# [2022-04-22 09:49:36,277] TRACE [gcp-bigquery-sink|task-0] write response contained errors: 
# {0=[BigQueryError{reason=invalid, location=f2, message=no such field: f2.}]} (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:178)
# [2022-04-22 09:49:36,277] DEBUG [gcp-bigquery-sink|task-0] re-attempting insertion (com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter:119)



#"autoCreateTables" : "false"
# [2022-04-22 09:33:08,245] DEBUG [gcp-bigquery-sink|task-0] Putting 0 records in the sink. (com.wepay.kafka.connect.bigquery.BigQuerySinkTask:238)
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
# [2022-04-22 09:34:08,246] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: A write thread has failed with an unrecoverable error (org.apache.kafka.connect.runtime.WorkerSinkTask:636)
# com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: A write thread has failed with an unrecoverable error
# Caused by: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.lambda$maybeThrowEncounteredError$0(KCBQThreadPoolExecutor.java:101)
#         at java.base/java.util.Optional.ifPresent(Optional.java:183)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredError(KCBQThreadPoolExecutor.java:100)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:236)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
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
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:125)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         ... 3 more
# [2022-04-22 09:34:08,247] WARN [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Offset commit failed during close (org.apache.kafka.connect.runtime.WorkerSinkTask:408)
# [2022-04-22 09:34:08,247] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Commit of offsets threw an unexpected exception for sequence number 8: null (org.apache.kafka.connect.runtime.WorkerSinkTask:270)
# com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: A write thread has failed with an unrecoverable error
# Caused by: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.lambda$maybeThrowEncounteredError$0(KCBQThreadPoolExecutor.java:101)
#         at java.base/java.util.Optional.ifPresent(Optional.java:183)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredError(KCBQThreadPoolExecutor.java:100)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.awaitCurrentTasks(KCBQThreadPoolExecutor.java:90)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.flush(BigQuerySinkTask.java:159)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.preCommit(BigQuerySinkTask.java:175)
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
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:125)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         ... 3 more
# [2022-04-22 09:34:08,247] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.lambda$maybeThrowEncounteredError$0(KCBQThreadPoolExecutor.java:101)
#         at java.base/java.util.Optional.ifPresent(Optional.java:183)
#         at com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor.maybeThrowEncounteredError(KCBQThreadPoolExecutor.java:100)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:236)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: table insertion failed for the following rows:
#         [row index 0] (location f2, reason: invalid): no such field: f2.
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:125)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         ... 3 more
# [2022-04-22 09:34:08,247] TRACE [gcp-bigquery-sink|task-0] Requesting shutdown for table write executor (com.wepay.kafka.connect.bigquery.BigQuerySinkTask:546)
# [2022-04-22 09:34:08,248] TRACE [gcp-bigquery-sink|task-0] Awaiting termination of table write executor (com.wepay.kafka.connect.bigquery.BigQuerySinkTask:549)
# [2022-04-22 09:34:08,251] TRACE [gcp-bigquery-sink|task-0] Shut down table write executor successfully (com.wepay.kafka.connect.bigquery.BigQuerySinkTask:551)
# [2022-04-22 09:34:08,251] TRACE [gcp-bigquery-sink|task-0] task.stop() (com.wepay.kafka.connect.bigquery.BigQuerySinkTask:533)
# [2022-04-22 09:34:08,252] INFO [gcp-bigquery-sink|task-0] [Consumer clientId=connector-consumer-gcp-bigquery-sink-0, groupId=connect-gcp-bigquery-sink] Revoke previously assigned partitions mytable2-0 (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:310)
# [2022-04-22 09:34:08,252] INFO [gcp-bigquery-sink|task-0] [Consumer clientId=connector-consumer-gcp-bigquery-sink-0, groupId=connect-gcp-bigquery-sink] Member connector-consumer-gcp-bigquery-sink-0-7bd8b8e8-5739-46f4-9a43-decc682420b0 sending LeaveGroup request to coordinator broker:9092 (id: 2147483646 rack: null) due to the consumer is being closed (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:1048)
# [2022-04-22 09:34:08,252] INFO [gcp-bigquery-sink|task-0] [Consumer clientId=connector-consumer-gcp-bigquery-sink-0, groupId=connect-gcp-bigquery-sink] Resetting generation due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:966)
# [2022-04-22 09:34:08,253] INFO [gcp-bigquery-sink|task-0] [Consumer clientId=connector-consumer-gcp-bigquery-sink-0, groupId=connect-gcp-bigquery-sink] Request joining group due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:988)
# [2022-04-22 09:34:08,254] INFO [gcp-bigquery-sink|task-0] Publish thread interrupted for client_id=connector-consumer-gcp-bigquery-sink-0 client_type=CONSUMER session= cluster=j4XAfrfyTCOfYnLEcV8q5Q group=connect-gcp-bigquery-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:285)
# [2022-04-22 09:34:08,254] INFO [gcp-bigquery-sink|task-0] Publishing Monitoring Metrics stopped for client_id=connector-consumer-gcp-bigquery-sink-0 client_type=CONSUMER session= cluster=j4XAfrfyTCOfYnLEcV8q5Q group=connect-gcp-bigquery-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:297)
# [2022-04-22 09:34:08,255] INFO [gcp-bigquery-sink|task-0] [Producer clientId=confluent.monitoring.interceptor.connector-consumer-gcp-bigquery-sink-0] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1217)
# [2022-04-22 09:34:08,257] INFO [gcp-bigquery-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-04-22 09:34:08,257] INFO [gcp-bigquery-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-04-22 09:34:08,258] INFO [gcp-bigquery-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-04-22 09:34:08,258] INFO [gcp-bigquery-sink|task-0] App info kafka.producer for confluent.monitoring.interceptor.connector-consumer-gcp-bigquery-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-04-22 09:34:08,258] INFO [gcp-bigquery-sink|task-0] Closed monitoring interceptor for client_id=connector-consumer-gcp-bigquery-sink-0 client_type=CONSUMER session= cluster=j4XAfrfyTCOfYnLEcV8q5Q group=connect-gcp-bigquery-sink (io.confluent.monitoring.clients.interceptor.MonitoringInterceptor:320)
# [2022-04-22 09:34:08,258] INFO [gcp-bigquery-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-04-22 09:34:08,258] INFO [gcp-bigquery-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-04-22 09:34:08,258] INFO [gcp-bigquery-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-04-22 09:34:08,259] INFO [gcp-bigquery-sink|task-0] App info kafka.consumer for connector-consumer-gcp-bigquery-sink-0 unregistered (org.apache.kafka.common.utils.AppInfoParser:83)
# [2022-04-22 09:34:08,259] INFO [gcp-bigquery-sink|task-0] [Producer clientId=connect-worker-producer] Closing the Kafka producer with timeoutMillis = 9223372036854775807 ms. (org.apache.kafka.clients.producer.KafkaProducer:1217)
# [2022-04-22 09:34:08,261] INFO [gcp-bigquery-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-04-22 09:34:08,261] INFO [gcp-bigquery-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-04-22 09:34:08,261] INFO [gcp-bigquery-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-04-22 09:34:08,261] INFO [gcp-bigquery-sink|task-0] App info kafka.producer for connect-worker-producer unregistered (org.apache.kafka.common.utils.AppInfoParser:83)