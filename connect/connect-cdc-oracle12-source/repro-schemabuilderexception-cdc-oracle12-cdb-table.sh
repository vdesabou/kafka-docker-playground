#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table-repro-schemabuilderexception.yml"


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
               "tasks.max":5,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
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
               "table.inclusion.regex": ".*CUSTOMERS",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 60s for cdc-oracle-source-cdb to read existing data"
sleep 60

log "Running SQL scripts"
for script in ${DIR}/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS: there should be 13 records"
set +e
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 13 > /tmp/result.log  2>&1
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
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 9

log "Update connector to include CUSTOMERS2 table"

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":5,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
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
               "table.inclusion.regex": ".*(CUSTOMERS|CUSTOMERS2)",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

exit 0
# no reproduction
# if I create another connector, then I see in logs
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector",
               "tasks.max":5,
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
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
               "table.inclusion.regex": ".*(CUSTOMERS|CUSTOMERS2)",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "confluent.topic.replication.factor":1
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb2/config | jq .

# [2021-07-22 15:52:25,073] ERROR Exception in RecordQueue thread (io.confluent.connect.oracle.cdc.util.RecordQueue)
# org.apache.kafka.connect.errors.ConnectException: Exception converting redo to change event. SQL: '  alter table CUSTOMERS2 add (
#     country VARCHAR(50)
#   );' INFO: USER DDL (PlSql=0 RecDep=0)
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:315)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.doGenerateChangeEvent(ChangeEventGenerator.java:431)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.execute(ChangeEventGenerator.java:212)
# 	at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)
# 	at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.SchemaBuilderException: Cannot create field because of field name duplication COUNTRY
# 	at org.apache.kafka.connect.data.SchemaBuilder.field(SchemaBuilder.java:330)
# 	at io.confluent.connect.oracle.cdc.OracleDdlParser.parseAndApply(OracleDdlParser.java:231)
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:301)
# 	... 7 more
# [2021-07-22 15:52:25,074] INFO Updating table CUSTOMERS with current schema Schema{STRUCT} with DDL   alter table CUSTOMERS add (
#     country VARCHAR(50)
#   ); (io.confluent.connect.oracle.cdc.OracleRedoLogReader)
# [2021-07-22 15:52:25,074] INFO Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics)
# [2021-07-22 15:52:25,074] INFO Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics)
# [2021-07-22 15:52:25,074] INFO Metrics reporters closed (org.apache.kafka.common.metrics.Metrics)
# [2021-07-22 15:52:25,075] INFO App info kafka.consumer for consumer-task-1-main-consumer-19 unregistered (org.apache.kafka.common.utils.AppInfoParser)
# [2021-07-22 15:52:25,075] ERROR Exception in RecordQueue thread (io.confluent.connect.oracle.cdc.util.RecordQueue)
# org.apache.kafka.connect.errors.ConnectException: Exception converting redo to change event. SQL: '  alter table CUSTOMERS add (
#     country VARCHAR(50)
#   );' INFO: USER DDL (PlSql=0 RecDep=0)
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:315)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.doGenerateChangeEvent(ChangeEventGenerator.java:431)
# 	at io.confluent.connect.oracle.cdc.ChangeEventGenerator.execute(ChangeEventGenerator.java:212)
# 	at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)
# 	at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.SchemaBuilderException: Cannot create field because of field name duplication COUNTRY
# 	at org.apache.kafka.connect.data.SchemaBuilder.field(SchemaBuilder.java:330)
# 	at io.confluent.connect.oracle.cdc.OracleDdlParser.parseAndApply(OracleDdlParser.java:231)
# 	at io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:301)
# 	... 7 more