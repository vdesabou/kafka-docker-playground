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

for component in producer-repro-milli
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-enablebatchload-with-gcs.repro-million-test.yml"

#FIXTHIS: table needs to be created first: "autoCreateTables" : "true" does not work with enableBatchLoad
# It can be run first and then delete with DELETE FROM `vincent-de-saboulin-lab.pgec2userds701.customer_avro` where true;

#####
## GCS
##

GCS_BUCKET_NAME=kafka-docker-playground-bucket-bq-${USER}${TAG}
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil mb -p $(cat ${KEYFILE} | jq -r .project_id) gs://$GCS_BUCKET_NAME
set -e

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/
set -e

#####
## BIG QUERY SINK
##


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

log "✨ Run the avro java producer which produces to topic customer_avro, only 10 messages"
docker exec -e NB_MESSAGES=10 producer-repro-milli bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > /dev/null 2>&1


log "Creating GCP BigQuery Sink connector, with autoCreateTables=true in order to create the table"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_avro",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "autoUpdateSchemas" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "allBQFieldsNullable": "false",
               "autoCreateTables": "true",
               "autoUpdateSchemas": "true",
               "includeKafkaData": "true",
               "bufferSize": "100000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "threadPoolSize": "10"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


sleep 120

curl -X DELETE localhost:8083/connectors/gcp-bigquery-sink

log "✨ Run the avro java producer which produces to topic customer_avro, 1M records"
docker exec producer-repro-milli bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > /dev/null 2>&1


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_avro",
               "gcsBucketName": "'"$GCS_BUCKET_NAME"'",
               "gcsFolderName": "",
               "enableBatchLoad": "customer_avro",
               "batchLoadIntervalSec": "60",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "autoUpdateSchemas" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "allBQFieldsNullable": "false",
               "includeKafkaData": "true",
               "bufferSize": "100000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "threadPoolSize": "10"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink-bulk/config | jq .

log "Sleeping 240 seconds"
sleep 240

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT COUNT(*) FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

# +---------+
# |   f0_   |
# +---------+
# | 1000020 |


# With asian characters (commit e9d7b71961525de6b49a10b6eccae25a9140037f), it's looping inifitely with:


# 2022-03-11 15:47:25,148] INFO [gcp-bigquery-sink-bulk|task-0] Successfully deleted 2703 blobs; failed to delete 0 blobs (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:301)
# [2022-03-11 15:47:25,257] INFO [gcp-bigquery-sink-bulk|task-0] Batch loaded 53 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)
# [2022-03-11 15:47:25,262] INFO [gcp-bigquery-sink-bulk|task-0] Batch loaded 53 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)
# [2022-03-11 15:47:25,273] INFO [gcp-bigquery-sink-bulk|task-0] Batch loaded 53 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)
# [2022-03-11 15:47:25,394] INFO [gcp-bigquery-sink-bulk|task-0] Batch loaded 53 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)
# [2022-03-11 15:47:25,459] INFO [gcp-bigquery-sink-bulk|task-0] Batch loaded 53 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)
# [2022-03-11 15:47:25,577] INFO [gcp-bigquery-sink-bulk|task-0] Batch loaded 53 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)
# [2022-03-11 15:47:25,581] INFO [gcp-bigquery-sink-bulk|task-0] Batch loaded 53 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)

# |   f0_   |
# +---------+
# | 2539905 |

# The consumer is being kicked out after 5 minutes, but keeps inserting requests to BQ