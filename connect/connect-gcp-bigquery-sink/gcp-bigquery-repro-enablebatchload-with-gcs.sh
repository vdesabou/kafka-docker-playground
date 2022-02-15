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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-enablebatchload-with-gcs.yml"

#####
## GCS SINK
##


GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
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
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/topics/gcs_topic
set -e

log "Sending messages to topic gcs_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic gcs_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'


log "Creating GCS Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic",
                    "gcs.bucket.name" : "'"$GCS_BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/tmp/keyfile.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/gcs-sink/config | jq .

sleep 10

log "Listing objects of in GCS"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil ls gs://$GCS_BUCKET_NAME/topics/gcs_topic/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -i --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gsutil cp gs://$GCS_BUCKET_NAME/topics/gcs_topic/partition=0/gcs_topic+0+0000000000.avro /tmp/gcs_topic+0+0000000000.avro

docker run --rm -v /tmp:/tmp actions/avro-tools tojson /tmp/gcs_topic+0+0000000000.avro

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



log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "gcs_topic",
               "gcsBucketName": "'"$GCS_BUCKET_NAME"'",
               "enableBatchLoad": "gcs_topic",
               "batchLoadIntervalSec": "30",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


# log "Sending messages to topic kcbq-quickstart1"
# seq -f "{\"f1\": \"value%g-`date`\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic kcbq-quickstart1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.gcs_topic;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

# [2022-02-15 15:16:18,628] INFO [gcp-bigquery-sink|task-0] Attempting to create table `pgvsaboulinds701`.`gcs_topic` with schema Schema{fields=[Field{name=f1, type=STRING, mode=REQUIRED, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:241)
# [2022-02-15 15:16:19,304] INFO [gcp-bigquery-sink|task-0] Batch loaded 10 rows (com.wepay.kafka.connect.bigquery.write.row.GCSToBQWriter:143)
# [2022-02-15 15:16:42,420] INFO [gcp-bigquery-sink|task-0] No blobs to delete (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:274)
# [2022-02-15 15:16:42,717] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/gcs_topic/partition=0/gcs_topic+0+0000000000.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:16:42,718] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/gcs_topic/partition=0/gcs_topic+0+0000000003.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:16:42,719] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/gcs_topic/partition=0/gcs_topic+0+0000000006.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:16:42,720] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000000.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:16:42,720] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000003.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:16:42,720] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000006.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:16:43,257] INFO [gcp-bigquery-sink|task-0] Triggered load job for table GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgvsaboulinds701, tableId=gcs_topic}} with 1 blobs. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:209)
# [2022-02-15 15:17:12,619] INFO [gcp-bigquery-sink|task-0] GCS To BQ job tally: 1 successful jobs, 0 failed jobs. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:257)
# [2022-02-15 15:17:12,619] INFO [gcp-bigquery-sink|task-0] Attempting to delete 1 blobs (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:278)
# [2022-02-15 15:17:13,168] INFO [gcp-bigquery-sink|task-0] Successfully deleted 1 blobs; failed to delete 0 blobs (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:301)
# [2022-02-15 15:17:13,357] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/gcs_topic/partition=0/gcs_topic+0+0000000000.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:17:13,357] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/gcs_topic/partition=0/gcs_topic+0+0000000003.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:17:13,358] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/gcs_topic/partition=0/gcs_topic+0+0000000006.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:17:13,358] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000000.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:17:13,358] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000003.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
# [2022-02-15 15:17:13,358] ERROR [gcp-bigquery-sink|task-0] Found blob kafkadockerplaygroundbucketvsaboulin701/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000006.avro with no metadata. (com.wepay.kafka.connect.bigquery.GCSToBQLoadRunnable:150)
