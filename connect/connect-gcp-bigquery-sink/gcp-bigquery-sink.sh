#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ] && [ -z "$KEYFILE_CONTENT" ]
then
     logerror "ERROR: either the file ${KEYFILE} is not present or environment variable KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${KEYFILE} ]
    then
        KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`
    else
        log "Creating ${KEYFILE} based on environment variable KEYFILE_CONTENT"
        echo -e "$KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${KEYFILE}
    fi
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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "kcbq-quickstart1",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "Sending messages to topic kcbq-quickstart1"
seq -f "{\"f1\": \"value%g-`date`\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic kcbq-quickstart1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.kcbq_quickstart1;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

log "Drop dataset $DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

docker rm -f gcloud-config