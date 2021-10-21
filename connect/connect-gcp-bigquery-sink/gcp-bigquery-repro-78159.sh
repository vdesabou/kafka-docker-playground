#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-78159
do
     log "Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package
done

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

sleep 90

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-78159.yml"

log "Activate TRACE logs for com.wepay.kafka.connect.bigquery"
curl --request PUT \
  --url http://localhost:8083/admin/loggers/com.wepay.kafka.connect.bigquery \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Create connector"

if version_gt $CONNECTOR_TAG "1.9.9"
then
     log "Creating GCP BigQuery Sink connector"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "customer-avro",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.enhanced.avro.schema.support": "false",
                    "defaultDataset" : "'"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "sanitizeFieldNames": "true",
                    "allBQFieldsNullable": "true",
                    "allowBigQueryRequiredFieldRelaxation": "true",
                    "allowNewBigQueryFields" : "true",
                    "allowBigQueryRequiredFieldRelaxation" : "true",
                    "allowSchemaUnionization" : "true",
                    "bigQueryRetryWait" : "10000",
                    "bigQueryRetry" : "3",
                    "keyfile" : "/tmp/keyfile.json",
                    "errors.tolerance" : "all",
                    "errors.log.enable" : "true",
                    "errors.log.include.messages" : "true",
                    "errors.deadletterqueue.topic.name" : "dlq",
                    "errors.deadletterqueue.topic.replication.factor": "1",
                    "errors.deadletterqueue.context.headers.enable" : "true"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink-78159/config | jq .
else
     log "Creating GCP BigQuery Sink connector"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "customer-avro",
                    "sanitizeTopics" : "true",
                    "autoCreateTables" : "true",
                    "autoUpdateSchemas" : "true",
                    "schemaRetriever" : "com.wepay.kafka.connect.bigquery.schemaregistry.schemaretriever.SchemaRegistrySchemaRetriever",
                    "schemaRegistryLocation": "http://schema-registry:8081",
                    "datasets" : ".*='"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
fi

log "Run the Java producer-78159"
docker exec producer-78159 bash -c "java -jar producer-78159-1.0.0-jar-with-dependencies.jar"

sleep 60

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log


# +----------------------------+-----------------+
# | createdDateTimestampMillis | createdDateDate |
# +----------------------------+-----------------+
# |        2015-01-25 07:20:50 |      2015-01-25 |
# |        2022-03-06 06:52:51 |      2022-03-06 |
# |        2026-02-12 21:02:35 |      2026-02-12 |
# |        2027-07-05 21:22:10 |      2027-07-05 |
# |        2024-04-27 17:37:30 |      2024-04-27 |
# |        2011-06-10 08:29:32 |      2011-06-10 |
# |        2025-12-04 16:28:24 |      2025-12-04 |
# |        2021-07-29 12:39:12 |      2021-07-29 |
# +----------------------------+-----------------+
