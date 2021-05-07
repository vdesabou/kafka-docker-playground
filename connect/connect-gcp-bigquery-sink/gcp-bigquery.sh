#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}
DATASET=${2:-MyDatasetTest}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop table $DATASET.kcbq_quickstart1, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query --use_legacy_sql=false "DROP TABLE $DATASET.kcbq_quickstart1;"
set -e

log "Sending messages to topic kcbq-quickstart1"
seq -f "{\"f1\": \"value%g-`date`\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic kcbq-quickstart1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "kcbq-quickstart1",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "autoUpdateSchemas" : "true",
               "schemaRetriever" : "com.wepay.kafka.connect.bigquery.retrieve.IdentitySchemaRetriever",
               "defaultDataset" : "'"$DATASET"'",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquey-sink/config | jq .

log "Sleeping 65 seconds"
sleep 65

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.kcbq_quickstart1;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

docker rm -f gcloud-config