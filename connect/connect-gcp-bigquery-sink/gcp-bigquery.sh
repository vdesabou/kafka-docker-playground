#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
verify_installed "gcloud"

PROJECT=${1:-vincent-de-saboulin-lab}
DATASET=${2:-MyDatasetTest}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     echo -e "\033[0;33mERROR: the file ${KEYFILE} file is not present!\033[0m"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mSending messages to topic kcbq-quickstart1\033[0m"
seq -f "{\"f1\": \"value%g-`date`\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic kcbq-quickstart1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'


echo -e "\033[0;33mCreating GCP BigQuery Sink connector\033[0m"
docker exec -e PROJECT="$PROJECT" -e DATASET="$DATASET" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "kcbq-quickstart1",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "autoUpdateSchemas" : "true",
                    "schemaRetriever" : "com.wepay.kafka.connect.bigquery.schemaregistry.schemaretriever.SchemaRegistrySchemaRetriever",
                    "schemaRegistryLocation": "http://schema-registry:8081",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "datasets" : ".*='"$DATASET"'",
                    "keyfile" : "/root/keyfiles/keyfile.json"
          }' \
     http://localhost:8083/connectors/kcbq-connect/config | jq .

sleep 10

echo -e "\033[0;33mDoing gsutil authentication\033[0m"
gcloud auth activate-service-account --key-file ${KEYFILE}

echo -e "\033[0;33mVerify data is in GCP BigQuery:\033[0m"
bq query "SELECT * FROM $DATASET.kcbq_quickstart1;"
