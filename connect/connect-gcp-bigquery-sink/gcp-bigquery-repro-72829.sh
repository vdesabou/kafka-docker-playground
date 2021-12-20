#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# this is a regression introduced between 6.0.0 and 6.0.1 coming from this PR https://github.com/confluentinc/schema-registry/pull/1625

# CP 6.0.0 and 2.0.8 -> ✅
# CP 6.0.0 and 2.1.6 -> ✅
# CP 6.0.1 and 2.1.6 -> ❌
# CP 6.0.3 and 2.1.6 -> ❌

# CP 6.1.3 and 2.1.6 -> ❌

# CP 6.2.0 and 2.0.8 -> ❌
# CP 6.2.0 and 2.1.6 -> ❌

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

for component in producer-72829
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-72829.yml"

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
                    "_comment": "discard.type.doc.default allows to restore previous behaviour, i.e set the doc description in BQ:",
                    "value.converter.discard.type.doc.default": "true",
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
          http://localhost:8083/connectors/gcp-bigquery-sink-72829/config | jq .
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

log "Run the Java producer-72829"
docker exec producer-72829 bash -c "java -jar producer-72829-1.0.0-jar-with-dependencies.jar"

sleep 60

log "Grep for doc description"
docker container logs connect | grep "Sed ut perspiciatis unde omnis"

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log

# [2021-09-08 14:16:30,024] TRACE [gcp-bigquery-sink|task-0] Validating schema change. Existing schema: Schema{fields=[Field{name=cookieId, type=STRING, mode=NULLABLE, description=null, policyTags=null}, Field{name=merchantReference, type=STRING, mode=NULLABLE, description=null, policyTags=null}]}; proposed Schema: Schema{fields=[Field{name=cookieId, type=STRING, mode=NULLABLE, description=null, policyTags=null}, Field{name=merchantReference, type=STRING, mode=NULLABLE, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:455)
# [2021-09-08 14:16:30,025] TRACE [gcp-bigquery-sink|task-0] Validating schema change. Existing schema: Schema{fields=[Field{name=cookieId, type=STRING, mode=NULLABLE, description=null, policyTags=null}, Field{name=merchantReference, type=STRING, mode=NULLABLE, description=null, policyTags=null}]}; proposed Schema: Schema{fields=[Field{name=cookieId, type=STRING, mode=NULLABLE, description=null, policyTags=null}, Field{name=merchantReference, type=STRING, mode=NULLABLE, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:455)
# [2021-09-08 14:16:30,041] INFO [gcp-bigquery-sink|task-0] Attempting to create table `pgvsaboulinds620`.`customer_avro` with schema Schema{fields=[Field{name=cookieId, type=STRING, mode=NULLABLE, description=null, policyTags=null}, Field{name=merchantReference, type=STRING, mode=NULLABLE, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:227)
