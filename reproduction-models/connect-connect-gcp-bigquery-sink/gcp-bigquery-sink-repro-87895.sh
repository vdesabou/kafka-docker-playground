#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in producer-87895 producer-87895-2
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

function wait_for_repro () {
     ERROR="$1"
     MAX_WAIT=600
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for error $ERROR to happen"
     docker container logs connect > /tmp/out.txt 2>&1
     while ! grep -i "$ERROR" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs connect > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show '$ERROR' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
     log "The problem has been reproduced !"
}


PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

DATASET=pgrepro87895
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

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/com.wepay.kafka.connect.bigquery \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "DEBUG"
# }'

function delete_connector () {
     curl --request DELETE \
               --url http://localhost:8083/connectors/gcp-bigquery-sink
}

function create_connector () {
     log "Creating GCP BigQuery Sink connector with autoCreateTables=false"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "topics" : "customer-avro",
                    "sanitizeTopics" : "true",
                    "sanitizeFieldNames": "true",
                    "autoCreateTables" : "true",
                    "defaultDataset" : "'"$DATASET"'",
                    "mergeIntervalMs": "5000",
                    "bufferSize": "100000",
                    "maxWriteSize": "10000",
                    "tableWriteWait": "1000",
                    "project" : "'"$PROJECT"'",
                    "keyfile" : "/tmp/keyfile.json",
                    "deleteEnabled": "true",
                    "upsertEnabled": "true",
                    "avroDataCacheSize": "101",
                    "kafkaKeyFieldName": "KEY",
                    "intermediateTableSuffix": "_intermediate",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url" : "http://schema-registry:8081",
                    "consumer.override.max.poll.records":  "10000",
                    "consumer.override.fetch.min.bytes": "1048576",
                    "consumer.override.fetch.max.wait.ms": "1000",
                    "consumer.override.session.timeout.ms": "60000"
               }' \
          http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .
}

# it is ok
log "Run the Java producer-87895 (10 records)"
docker exec producer-87895 bash -c "java -jar producer-87895-1.0.0-jar-with-dependencies.jar"
create_connector

log "sleep 150 seconds"
sleep 150

delete_connector
log "Run the Java producer-87895-2 (only one tombstone)"
docker exec producer-87895-2 bash -c "java -jar producer-87895-2-1.0.0-jar-with-dependencies.jar"
# it is not ok, as last record is a tombstone
create_connector

wait_for_repro "Failed to unionize schemas of records for the table"

# Exception in thread "pool-10-thread-1" com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Failed to unionize schemas of records for the table GenericData{classInfo=[datasetId, projectId, tableId], {datasetId=pgrepro, tableId=customer_avro2__intermediate_0_437011d3_a297_4d6d_a2ef_13c9e2d0edf1_1642152694641}}
# Caused by: Could not convert to BigQuery schema with a batch of tombstone records.
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getTableInfo(SchemaManager.java:289)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createTable(SchemaManager.java:232)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.attemptTableCreate(AdaptiveBigQueryWriter.java:161)
#         at com.wepay.kafka.connect.bigquery.write.row.UpsertDeleteBigQueryWriter.attemptTableCreate(UpsertDeleteBigQueryWriter.java:82)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:102)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:112)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:93)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.wepay.kafka.connect.bigquery.exception.BigQueryConnectException: Could not convert to BigQuery schema with a batch of tombstone records.
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getAndValidateProposedSchema(SchemaManager.java:307)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getTableInfo(SchemaManager.java:286)
#         ... 9 more


# delete_connector
# log "Run the Java producer-87895 (10 records)"
# docker exec producer-87895 bash -c "java -jar producer-87895-1.0.0-jar-with-dependencies.jar"
# # it is ok now since there are valid records since then
# create_connector

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log

# -----+-------------------------+---------+
# | count | first_name |  last_name  |         address         | KEY_KEY |
# +-------+------------+-------------+-------------------------+---------+
# |     1 | Estefania  | Parisian    | 90115 Beahan Road       |       1 |
# |     7 | Jaida      | Williamson  | 746 Jeanette Knoll      |       7 |
# |     6 | Beulah     | Durgan      | 3271 Mueller Crescent   |       6 |
# |     3 | Nicole     | Reichel     | 74216 Jewel Ferry       |       3 |
# |     4 | Caterina   | Gleichner   | 1446 VonRueden Villages |       4 |
# |     0 | Amparo     | Von         | 029 Alfredo Lodge       |       0 |
# |     2 | Kareem     | Greenfelder | 5160 O'Conner Street    |       2 |
# |     5 | Stephania  | Lynch       | 3341 Kutch Shoals       |       5 |
# |     8 | Rosie      | Gerlach     | 3291 Lowe Mount         |       8 |
# |     9 | Wiley      | Berge       | 8593 Arnaldo Point      |       9 |
# +-------+------------+-------------+-------------------------+---------+

delete_connector

log "Reset offset for customer-avro to 9 (the record before tombstone)"
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-gcp-bigquery-sink --describe
# GROUP                     TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                                                 HOST            CLIENT-ID
# connect-gcp-bigquery-sink customer-avro   0          10              11              1               connector-consumer-gcp-bigquery-sink-0-e3e3f0bf-c814-4814-a0e3-85e54b027abb /172.24.0.7     connector-consumer-gcp-bigquery-sink-0

# GCP has 10 records

docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-gcp-bigquery-sink --to-offset 9 --topic customer-avro --reset-offsets --dry-run
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-gcp-bigquery-sink --to-offset 9 --topic customer-avro --reset-offsets --execute
docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-gcp-bigquery-sink --describe

# GROUP                     TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
# connect-gcp-bigquery-sink customer-avro   0          9              11              1               -               -               -

# restart connector

log "restart failed task"
create_connector


sleep 120

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.customer_avro;" > /tmp/result.log  2>&1
cat /tmp/result.log

# +-------+------------+-------------+-------------------------+---------+
# | count | first_name |  last_name  |         address         | KEY_KEY |
# +-------+------------+-------------+-------------------------+---------+
# |     1 | Estefania  | Parisian    | 90115 Beahan Road       |       1 |
# |     7 | Jaida      | Williamson  | 746 Jeanette Knoll      |       7 |
# |     6 | Beulah     | Durgan      | 3271 Mueller Crescent   |       6 |
# |     3 | Nicole     | Reichel     | 74216 Jewel Ferry       |       3 |
# |     4 | Caterina   | Gleichner   | 1446 VonRueden Villages |       4 |
# |     0 | Amparo     | Von         | 029 Alfredo Lodge       |       0 |
# |     2 | Kareem     | Greenfelder | 5160 O'Conner Street    |       2 |
# |     5 | Stephania  | Lynch       | 3341 Kutch Shoals       |       5 |
# |     8 | Rosie      | Gerlach     | 3291 Lowe Mount         |       8 |
# |     9 | Wiley      | Berge       | 8593 Arnaldo Point      |       9 |
# +-------+------------+-------------+-------------------------+---------+

docker exec broker kafka-consumer-groups --bootstrap-server broker:9092 --group connect-gcp-bigquery-sink --describe

# GROUP                     TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
# connect-gcp-bigquery-sink customer-avro   0          11              11              1               -               -               -
