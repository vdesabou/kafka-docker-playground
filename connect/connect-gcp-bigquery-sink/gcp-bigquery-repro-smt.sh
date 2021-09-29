#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


function wait_for_repro () {
     MAX_WAIT=600
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for error no such field: statusAsString to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep "message=no such field: statusAsString" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'message=no such field: statusAsString' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}

for component in producer-v1
do
     if [ ! -f ${DIR}/${component}/target/${component}-1.0.0-jar-with-dependencies.jar ]
     then
          log "Building jar for ${component}"
          docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package
     fi
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

sleep 60

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-66277.yml"

log "Activate TRACE logs for com.wepay.kafka.connect.bigquery"
curl --request PUT \
  --url http://localhost:8083/admin/loggers/com.wepay.kafka.connect.bigquery \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Create connector"
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
               "errors.deadletterqueue.context.headers.enable" : "true",
               "transforms": "HoistField,InsertFieldStatic,InsertFieldOffset",
               "transforms.HoistField.type": "org.apache.kafka.connect.transforms.HoistField$Value",
               "transforms.HoistField.field": "payload",
               "transforms.InsertFieldStatic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
               "transforms.InsertFieldStatic.static.field": "MessageSource",
               "transforms.InsertFieldStatic.static.value": "Kafka Connect framework",
               "transforms.InsertFieldOffset.type": "org.apache.kafka.connect.transforms.InsertField$Value",
               "transforms.InsertFieldOffset.offset.field": "offset"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink2/config | jq .


log "Run the Java producer-v1"
docker exec producer-v1 bash -c "java -jar producer-v1-1.0.0-jar-with-dependencies.jar"

sleep 30

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "mergedTomatoe_truDta_bu" /tmp/result.log

