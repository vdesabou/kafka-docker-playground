#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PROJECT=${1:-vincent-de-saboulin-lab} 
DATASET=${1:-MyDatasetTest} 

${DIR}/../scripts/reset-cluster.sh

echo "Sending messages to topic kcbq-quickstart1"
seq -f "{\"f1\": \"value%g\"}" 10 | docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic kcbq-quickstart1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'


echo "Creating GCP BigQuery Sink connector"
docker-compose exec -e PROJECT="$PROJECT" -e DATASET="$DATASET" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "kcbq-connect",
               "config": {
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
                    "keyfile" : "/root/keyfile.json"
          }}' \
     http://localhost:8083/connectors | jq .

echo "Verify data is in GCP BigQuery:"
bq query "SELECT * FROM $DATASET.kcbq_quickstart1;"
