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

DATASET=pgvincent88043
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

# set +e
# log "Drop dataset $DATASET, this might fail"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
# set -e

# log "Create dataset $PROJECT.$DATASET"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"

# table should exist with f1 STRING	NULLABLE	

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "my_topic",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "false",
               "allowBigQueryRequiredFieldRelaxation": "true",
               "allowNewBigQueryFields" : "true",
               "allowSchemaUnionization" : "false",
               "allBQFieldsNullable" : "false",
               "deleteEnabled": "false",
               "upsertEnabled": "false",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",
               "errors.tolerance" : "all",
               "errors.log.enable" : "true",
               "errors.log.include.messages" : "true",
               "errors.deadletterqueue.topic.name" : "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable" : "true"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "Sending messages to topic my_topic which can be null"
seq -f "{\"f1\": {\"string\": \"value%g-`date`\"}}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"fields":[{"default":null,"type":["null","string"],"name":"f1"}],"type":"record","name":"myrecord"}'
echo "{\"f1\": null}" | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"fields":[{"default":null,"type":["null","string"],"name":"f1"}],"type":"record","name":"myrecord"}'

log "Sleeping 30 seconds"
sleep 30

log "Change compatibility mode to NONE"
curl --request PUT \
  --url http://localhost:8081/config \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{
    "compatibility": "NONE"
}'

log "Sending messages to topic my_topic which cannot be null"
seq -f "{\"f1\": \"value%g-`date`\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic my_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.my_topic;" > /tmp/result.log  2>&1
cat /tmp/result.log