#!/bin/bash
set -e

#CP 5.4.2
# CDC 1.2.1
# BQ 2.1.5
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


if [ -z "$CI" ]
then
     # not running with github actions
     if test -z "$(docker images -q oracle/database:12.2.0.1-ee)"
     then
          if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
          then
               logerror "ERROR: ${DIR}/linuxx64_12201_database.zip is missing. It must be downloaded manually in order to acknowledge user agreement"
               exit 1
          fi
          log "Building oracle/database:12.2.0.1-ee docker image..it can take a while...(more than 15 minutes!)"
          OLDDIR=$PWD
          rm -rf ${DIR}/docker-images
          git clone https://github.com/oracle/docker-images.git

          cp ${DIR}/linuxx64_12201_database.zip ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles/12.2.0.1/linuxx64_12201_database.zip
          cd ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles
          ./buildContainerImage.sh -v 12.2.0.1 -e
          rm -rf ${DIR}/docker-images
          cd ${OLDDIR}
     fi
fi

export ORACLE_IMAGE="oracle/database:12.2.0.1-ee"
if [ ! -z "$CI" ]
then
     # if this is github actions, use private image.
     export ORACLE_IMAGE="vdesabou/oracle12"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-repro-pipeline-bigquery-71607.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
log "Oracle DB has started!"

# Create a redo-log-topic. Please make sure you create a topic with the same name you will use for "redo.log.topic.name": "redo-log-topic"
# CC-13104
docker exec connect kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
log "redo-log-topic is created"
sleep 5


log "Creating Oracle source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":2,
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "key.converter": "org.apache.kafka.connect.json.JsonConverter",
               "key.template": "${primaryKeyStruct}",
               "emit.tombstone.on.delete": "true",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "ORCLCDB",
               "oracle.username": "C##MYUSER",
               "oracle.password": "mypassword",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 60s for cdc-oracle-source-cdb to read existing data"
sleep 60

log "Running SQL scripts"
for script in ${DIR}/sample-sql-scripts/*
do
     $script "ORCLCDB"
done

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS: there should be 13 records"
set +e
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 13 > /tmp/result.log  2>&1
set -e
cat /tmp/result.log
log "Check there is 5 snapshots events"
if [ $(grep -c "op_type\":{\"string\":\"R\"}" /tmp/result.log) -ne 5 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 3 insert events"
if [ $(grep -c "op_type\":{\"string\":\"I\"}" /tmp/result.log) -ne 3 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 4 update events"
if [ $(grep -c "op_type\":{\"string\":\"U\"}" /tmp/result.log) -ne 4 ]
then
     logerror "Did not get expected results"
     exit 1
fi
log "Check there is 1 delete events"
if [ $(grep -c "op_type\":{\"string\":\"D\"}" /tmp/result.log) -ne 1 ]
then
     logerror "Did not get expected results"
     exit 1
fi

log "Verifying topic redo-log-topic: there should be 9 records"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic redo-log-topic --from-beginning --max-messages 9


if version_gt $CONNECTOR_TAG "1.9.9"
then
     log "Creating GCP BigQuery Sink connector"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "kafkaKeyFieldName": "ID",
                    "deleteEnabled": "true",
                    "topics" : "ORCLCDB.C__MYUSER.CUSTOMERS",
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
          http://localhost:8083/connectors/gcp-bigquery-sink6/config | jq .
else
     log "Creating GCP BigQuery Sink connector"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
                    "tasks.max" : "1",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "topics" : "ORCLCDB.C__MYUSER.CUSTOMERS",
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

log "Sleeping 125 seconds"
sleep 125

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" query "SELECT * FROM $DATASET.ORCLCDB_C__MYUSER_CUSTOMERS;"

# log "Drop dataset $DATASET"
# docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"

# docker rm -f gcloud-config


# [2021-09-13 12:10:00,695] INFO [gcp-bigquery-sink5|task-0] Attempting to create intermediate table `pgec2userds620`.`ORCLCDB_C__MYUSER_CUSTOMERS_tmp_0_b0d22c34_25de_4b43_af9f_a04a1d84ca6f_1631534996795` with schema Schema{fields=[Field{name=value, type=RECORD, mode=NULLABLE, description=null, policyTags=null}, Field{name=key, type=RECORD, mode=REQUIRED, description=null, policyTags=null}, Field{name=i, type=INTEGER, mode=REQUIRED, description=null, policyTags=null}, Field{name=partitionTime, type=TIMESTAMP, mode=NULLABLE, description=null, policyTags=null}, Field{name=batchNumber, type=INTEGER, mode=REQUIRED, description=null, policyTags=null}]} (com.wepay.kafka.connect.bigquery.SchemaManager:227)
# [2021-09-13 12:10:01,429] ERROR [gcp-bigquery-sink5|task-0] Task failed with java.lang.IllegalArgumentException error: Multiple entries with same key: ID=17 and ID=0 (com.wepay.kafka.connect.bigquery.write.batch.KCBQThreadPoolExecutor:70)
# Exception in thread "pool-18-thread-1" java.lang.IllegalArgumentException: Multiple entries with same key: ID=17 and ID=0
#         at com.google.common.collect.RegularImmutableMap.duplicateKeyException(RegularImmutableMap.java:181)
#         at com.google.common.collect.RegularImmutableMap.createHashTable(RegularImmutableMap.java:120)
#         at com.google.common.collect.RegularImmutableMap.create(RegularImmutableMap.java:81)
#         at com.google.common.collect.ImmutableMap$Builder.build(ImmutableMap.java:341)
#         at com.google.cloud.bigquery.FieldList.<init>(FieldList.java:48)
#         at com.google.cloud.bigquery.FieldList.of(FieldList.java:106)
#         at com.google.cloud.bigquery.Schema.of(Schema.java:79)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getBigQuerySchema(SchemaManager.java:600)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.convertRecordSchema(SchemaManager.java:356)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getAndValidateProposedSchema(SchemaManager.java:306)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.getTableInfo(SchemaManager.java:280)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.updateSchema(SchemaManager.java:252)
#         at com.wepay.kafka.connect.bigquery.SchemaManager.createOrUpdateTable(SchemaManager.java:210)
#         at com.wepay.kafka.connect.bigquery.write.row.UpsertDeleteBigQueryWriter.attemptTableCreate(UpsertDeleteBigQueryWriter.java:87)
#         at com.wepay.kafka.connect.bigquery.write.row.AdaptiveBigQueryWriter.performWriteRequest(AdaptiveBigQueryWriter.java:115)
#         at com.wepay.kafka.connect.bigquery.write.row.BigQueryWriter.writeRows(BigQueryWriter.java:118)
#         at com.wepay.kafka.connect.bigquery.write.batch.TableWriter.run(TableWriter.java:96)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
