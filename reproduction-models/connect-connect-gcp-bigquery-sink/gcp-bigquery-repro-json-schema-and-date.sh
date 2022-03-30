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

for component in producer-repro-json
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-json-schema-and-date.yml"


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "customer_json_schema",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5000",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json",

               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "transforms": "TimestampConverter",
               "transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
               "transforms.TimestampConverter.format": "yyyy-MM-dd",
               "transforms.TimestampConverter.field": "report_date",
               "transforms.TimestampConverter.target.type": "Date"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .

# [2022-03-30 16:59:16,205] INFO [gcp-bigquery-sink|task-0] Attempting to create table `pgec2userds701`.`customer_json_schema` with schema Schema{fields=[Field{name=surname, type=STRING, mode=NULLABLE, description=null, policyTags=null}, Field{name=name, type=STRING, mode=NULLABLE, description=null, policyTags=null}, Field{name=report_date, type=DATE, mode=NULLABLE, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:241)

log "✨ Run the json-schema java producer which produces to topic customer_json_schema"
docker exec producer-repro-json bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"


log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_json_schema;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

log "Drop dataset $DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

docker rm -f gcloud-config