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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "a-topic",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "false",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5010",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "true"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink3/config | jq .

exit 0

docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
1,{"payload":{"price":25,"product":"foo1","id":100,"quantity":100},"schema":{"fields":[{"optional":false,"type":"int32","field":"id"},{"optional":false,"type":"string","field":"product"},{"optional":false,"type":"int32","field":"quantity"},{"optional":false,"type":"int32","field":"price"}],"type":"struct","name":"orders","optional":false}}
EOF

# log "Sleeping 125 seconds"
# sleep 125

# log "Verify data is in GCP BigQuery:"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.a_topic;" > /tmp/result.log  2>&1
# cat /tmp/result.log
# grep "record1" /tmp/result.log


# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/org.apache.kafka.connect.runtime.WorkerSinkTask \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "TRACE"
# }'


# docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic a-topic --property parse.key=true --property key.separator=, << EOF
# 1,{"payload":{"price":25,"product":"foo1","id":100},"schema":{"fields":[{"optional":false,"type":"int32","field":"id"},{"optional":false,"type":"string","field":"product"},{"optional":false,"type":"int32","field":"price"}],"type":"struct","name":"orders","optional":false}}
# EOF

# [2022-01-14 14:40:49,957] TRACE [gcp-bigquery-sink3|task-0] WorkerSinkTask{id=gcp-bigquery-sink3-0} Consuming and converting message in topic 'a-topic' partition 0 at offset 2 and timestamp 1642171081833 (org.apache.kafka.connect.runtime.WorkerSinkTask:489)
# [2022-01-14 14:40:49,957] TRACE [gcp-bigquery-sink3|task-0] WorkerSinkTask{id=gcp-bigquery-sink3-0} Applying transformations to record in topic 'a-topic' partition 0 at offset 2 and timestamp 1642171081833 with key 1 and value Struct{id=100,product=foo1,price=25} (org.apache.kafka.connect.runtime.WorkerSinkTask:536)
# [2022-01-14 14:40:49,957] TRACE [gcp-bigquery-sink3|task-0] WorkerSinkTask{id=gcp-bigquery-sink3-0} Delivering batch of 3 messages to task (org.apache.kafka.connect.runtime.WorkerSinkTask:602)
# [2022-01-14 14:40:50,264] TRACE [gcp-bigquery-sink3|task-0] WorkerSinkTask{id=gcp-bigquery-sink3-0} Polling consumer with timeout 56654 ms (org.apache.kafka.connect.runtime.WorkerSinkTask:328)
# [2022-01-14 14:40:50,447] WARN [gcp-bigquery-sink3|task-0] You may want to enable schema updates by specifying allowNewBigQueryFields=true or allowBigQueryRequiredFieldRelaxation=true in the properties file (com.wepay.kafka.connect.bigquery.write.row.SimpleBigQueryWriter:69)
# Exception in thread "pool-8-thread-1" com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: table insertion failed for the following rows:
#         [row index 0] (location , reason: stopped): 
#         [row index 1] (location , reason: stopped): 
#         [row index 2] (location , reason: invalid): Missing required field: Msg_0_CLOUD_QUERY_TABLE.quantity.
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:125)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
