#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-87895
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


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-87895.yml"


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
               "keyfile" : "/tmp/keyfile.json",
               "deleteEnabled": "true",
               "autoCreateTables" : "true",
               "kafkaKeyFieldName": "KEY",
               "intermediateTableSuffix": "_intermediate",
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url" : "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .


log "Run the Java producer-87895"
docker exec producer-87895 bash -c "java -jar producer-87895-1.0.0-jar-with-dependencies.jar"


log "Sleeping 60 seconds"
sleep 60

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log


# -----------+----------------------+-------------+----------------------+
# |          ID          |       DELETED        |      DAYSAFTER       | CREATEDDATE | MODIFIEDDATE | NAME | STARTEXPIRYDATE | STATUS | TYPE | PUBLISHINGTYPEHARDCOPY |  COUPONFORREJECTION  | USECATBASEDMINAMOUNT | DESCRIPTION |        KEY_ID        |
# +----------------------+----------------------+----------------------+-------------+--------------+------+-----------------+--------+------+------------------------+----------------------+----------------------+-------------+----------------------+
# | -5237980416576129062 |  1326634973105178603 | -3758321679654915806 | y           | edUs         | Fwd  | kelQ            | b      | xeTe |   -7771300887898959616 | -1694783153133139413 |  2746989241534039508 | Q           |  -167885730524958550 |
# | -5106534569952410475 |  -167885730524958550 |  4672433029010564658 | eOM         | tThy         | hV   | NLW             | UZNR   | cBaQ |   -7216359497931550918 | -3581075550420886390 | -2298228485105199876 | KxI         | -5106534569952410475 |
# |  -457112246358890037 |  1210033231312349320 |  1282378635546458216 | O           | v            | aS   | cfqI            | OOm    | aa   |    1674084292433445352 |  7830028867000074426 | -2317076407365535282 | Jx          |  4672433029010564658 |
# | -7837950195727116076 |  7314076204812145092 |  4765075071605135204 | k           | yv           | Rn   | LR              | Y      | tGK  |    2818517680934561261 |  4804084248667953465 |  8516528816379729956 | b           | -7216359497931550918 |
# |  5592478093667638902 | -5625430285771842101 |  7900063374667700860 | g           | dnt          | u    | g               | zvv    | KAX  |    -636830170795397064 | -5064906505645556577 |  6182569346087950473 | L           | -3758321679654915806 |
# | -4794565267078688161 | -1079643762651135835 | -3210848112367399599 | UfP         | xx           | QHeW | KEJ             | dp     | HYZG |   -8961286854129169704 | -7487977810896584711 |  4210921260047574683 | ht          |  1326634973105178603 |
# |  8099979915178793733 |  3899741886324459877 | -7116529718146323612 | gic         | ZaH          | C    | BRQD            | Sx     | VLh  |     617189662771004779 | -5738853485602064100 | -5827090338538224485 | pfQ         | -3581075550420886390 |
# | -7845324134759045378 |  7156814178861103683 |  3488800780984115528 | ygj         | bUMa         | AIKK | Ikk             | njW    | E    |     492926413741371804 |   582119640634903450 | -3128420272228665997 | XJ          | -5237980416576129062 |
# |  1388282375910965670 |  -981261886383069152 |  8058951195138745325 | GTM         | DYp          | sB   | Z               | x      | v    |   -5648106443147652010 | -5969394034050049196 | -6847734019527209621 | fBoe        | -2298228485105199876 |
# +----------------------+----------------------+----------------------+-------------+--------------+------+-----------------+--------+------+------------------------+----------------------+----------------------+-------------+----------------------+

