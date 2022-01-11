#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-87791
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

DATASET=pgrepro
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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-87791.yml"

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
                    "defaultDataset" : "'"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
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

log "Run the Java producer-87791"
docker exec producer-87791 bash -c "java -jar producer-87791-1.0.0-jar-with-dependencies.jar"

log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "MODIFIEDDATE" /tmp/result.log

log "Drop dataset $DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

docker rm -f gcloud-config

# +----------------------+----------------------+----------------------+-------------+--------------+------+-----------------+--------+------+----------------------+------------------------+----------------------+----------------------+-------------+
# |          ID          |       DELETED        |      DAYSAFTER       | CREATEDDATE | MODIFIEDDATE | NAME | STARTEXPIRYDATE | STATUS | TYPE |       EXCLUDE        | PUBLISHINGTYPEHARDCOPY |  COUPONFORREJECTION  | USECATBASEDMINAMOUNT | DESCRIPTION |
# +----------------------+----------------------+----------------------+-------------+--------------+------+-----------------+--------+------+----------------------+------------------------+----------------------+----------------------+-------------+
# | -6847734019527209621 | -7845324134759045378 |  7156814178861103683 | GTM         | DYp          | sB   | Z               | x      | v    |  3488800780984115528 |     492926413741371804 |   582119640634903450 | -3128420272228665997 | fBoe        |
# |  1282378635546458216 |  1674084292433445352 |  7830028867000074426 | O           | v            | aS   | cfqI            | OOm    | aa   | -2317076407365535282 |   -7837950195727116076 |  7314076204812145092 |  4765075071605135204 | Jx          |
# |  2818517680934561261 |  4804084248667953465 |  8516528816379729956 | k           | yv           | Rn   | LR              | Y      | tGK  |  8099979915178793733 |    3899741886324459877 | -7116529718146323612 |   617189662771004779 | b           |
# | -5738853485602064100 | -5827090338538224485 |  1388282375910965670 | gic         | ZaH          | C    | BRQD            | Sx     | VLh  |  -981261886383069152 |    8058951195138745325 | -5648106443147652010 | -5969394034050049196 | pfQ         |
# | -4794565267078688161 | -1079643762651135835 | -3210848112367399599 | ygj         | bUMa         | AIKK | Ikk             | njW    | E    | -8961286854129169704 |   -7487977810896584711 |  4210921260047574683 |  5592478093667638902 | XJ          |
# |  4530030225633203497 | -5622147162416175951 |  4047834147411242470 | g           | dnt          | u    | g               | zvv    | KAX  |  2050976543698204552 |   -8000419653771970126 | -8952004768583126073 |  2851692972699431722 | L           |
# | -8262935286139685279 |  4854543426611963037 |  5181313837801002933 | hML         | lN           | gN   | fZ              | B      | dyFG |  7668428197995251475 |    3098185324426972211 | -3082813733013320303 |  5577812605819267909 | Ra          |
# +----------------------+----------------------+----------------------+-------------+--------------+------+-----------------+--------+------+----------------------+------------------------+----------------------+----------------------+-------------+