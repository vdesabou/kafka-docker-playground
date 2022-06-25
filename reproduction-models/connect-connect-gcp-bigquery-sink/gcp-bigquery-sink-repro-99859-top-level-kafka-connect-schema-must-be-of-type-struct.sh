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

for component in producer-repro-99859
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-99859-top-level-kafka-connect-schema-must-be-of-type-struct.yml"


curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_avro",
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
               "key.converter" : "org.apache.kafka.connect.storage.StringConverter",
               "transforms": "HoistFieldKey",
               "transforms.HoistFieldKey.type": "org.apache.kafka.connect.transforms.HoistField$Key",
               "transforms.HoistFieldKey.field": "usr_user_id"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-99859 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

# without SMT HoistField:
# repro: key is String "Struct{usr_user_id=1}"
# [2022-04-06 12:51:13,662] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: com.wepay.kafka.connect.bigquery.exception.ConversionConnectException: Top-level Kafka Connect schema must be of type 'struct'
#         at com.wepay.kafka.connect.bigquery.convert.BigQueryRecordConverter.convertRecord(BigQueryRecordConverter.java:88)
#         at com.wepay.kafka.connect.bigquery.convert.BigQueryRecordConverter.convertRecord(BigQueryRecordConverter.java:49)
#         at com.wepay.kafka.connect.bigquery.utils.SinkRecordConverter.getUpsertDeleteRow(SinkRecordConverter.java:104)
#         at com.wepay.kafka.connect.bigquery.utils.SinkRecordConverter.getRecordRow(SinkRecordConverter.java:73)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter$Builder.addRow(TableWriter.java:193)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:272)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more




log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log

# with SMT:

# [2022-04-06 13:00:03,213] INFO [gcp-bigquery-sink|task-0] Attempting to create intermediate table `pgec2userds702`.`customer_avro_tmp_0_17da2b67_5b09_43a2_aab1_376816f95d5b_1649249998706` with schema Schema{fields=[Field{name=value, type=RECORD, mode=NULLABLE, description=null, policyTags=null}, Field{name=key, type=RECORD, mode=REQUIRED, description=null, policyTags=null}, Field{name=i, type=INTEGER, mode=REQUIRED, description=null, policyTags=null}, Field{name=partitionTime, type=TIMESTAMP, mode=NULLABLE, description=null, policyTags=null}, Field{name=batchNumber, type=INTEGER, mode=REQUIRED, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:241)
# [2022-04-06 13:00:03,904] INFO [gcp-bigquery-sink|task-0] Attempting to create table `pgec2userds702`.`customer_avro` with schema Schema{fields=[Field{name=count, type=INTEGER, mode=REQUIRED, description=null, policyTags=null}, Field{name=first_name, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=last_name, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=address, type=STRING, mode=REQUIRED, description=null, policyTags=null}, Field{name=KEY, type=RECORD, mode=NULLABLE, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:241)

# ---+---------------+-----------------------+
# |        count         |   first_name   |   last_name    |    address    |    KEY_usr_user_id    |
# +----------------------+----------------+----------------+---------------+-----------------------+
# |  4672433029010564658 | YtGKbgicZaH    | CB             | RQDSxVLhpfQG  | Struct{usr_user_id=2} |
# |  -167885730524958550 | wdkelQbxe      | TeQOvaScfqIO   | OmaaJxkyvRnLR | Struct{usr_user_id=1} |
# | -7216359497931550918 | TMDYpsBZx      | vfBoeygjbUMaA  | IKK           | Struct{usr_user_id=3} |
# | -5106534569952410475 | eOMtThyhVNL    | WUZNRcBaQKxIye | dUsF          | Struct{usr_user_id=0} |
# |  1326634973105178603 | Raj            | VfJN           | onEnOin       | Struct{usr_user_id=7} |
# | -3758321679654915806 | ZjUfzQh        | dgL            | LfDTDGspD     | Struct{usr_user_id=8} |
# | -5237980416576129062 | vKAXLhMLl      | NgNfZB         | dyFG          | Struct{usr_user_id=6} |
# | -3581075550420886390 | IkknjWEXJUfPxx | Q              | H             | Struct{usr_user_id=4} |
# | -2298228485105199876 | eW             | KEJdpH         | YZGhtgdntugzv | Struct{usr_user_id=5} |
# | -7771300887898959616 | b              | QvBQYuxiXX     | VytGCxzVll    | Struct{usr_user_id=9} |
# +----------------------+----------------+----------------+---------------+-----------------------+
