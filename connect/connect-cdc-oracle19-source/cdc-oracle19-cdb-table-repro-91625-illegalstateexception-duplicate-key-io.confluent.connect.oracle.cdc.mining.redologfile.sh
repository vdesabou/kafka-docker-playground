#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "$(pwd)/ora-setup-scripts-cdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-91625-illegalstateexception-duplicate-key-io.confluent.connect.oracle.cdc.mining.redologfile.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=2500
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
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
sleep 60

log "Set multiple LOG_ARCHIVE_DEST_x"
docker exec -i oracle bash -c "mkdir /tmp/redolog;ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA

ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=/opt/oracle/product/19c/dbhome_1/dbs/';
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='LOCATION=/tmp/redolog';

  exit;
EOF

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
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "auto"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 60s for connector to read existing data"
sleep 60

log "Running SQL scripts"
for script in ${DIR}/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

# [2022-02-07 16:31:55,841] ERROR [cdc-oracle-source-cdb|task-0] WorkerSourceTask{id=cdc-oracle-source-cdb-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Error while polling for records
#         at io.confluent.connect.oracle.cdc.util.RecordQueue.poll(RecordQueue.java:372)
#         at io.confluent.connect.oracle.cdc.OracleCdcSourceTask.poll(OracleCdcSourceTask.java:489)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:308)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 32768 to read redo log from jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle)(PORT=1521))(CONNECT_DATA=(SID=ORCLCDB))) with user 'C##MYUSER' (pool=oracle-cdc-source:cdc-oracle-source-cdb-0): Duplicate key 1_7_1088159216.dbf (attempted merging values io.confluent.connect.oracle.cdc.mining.RedoLogFile@216a4111 and io.confluent.connect.oracle.cdc.mining.RedoLogFile@71af15b8)
#         at io.confluent.connect.oracle.cdc.OracleRedoLogReader.readRedoLogs(OracleRedoLogReader.java:105)
#         at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)
#         at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
#         ... 3 more
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 32768 to read redo log from jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle)(PORT=1521))(CONNECT_DATA=(SID=ORCLCDB))) with user 'C##MYUSER' (pool=oracle-cdc-source:cdc-oracle-source-cdb-0): Duplicate key 1_7_1088159216.dbf (attempted merging values io.confluent.connect.oracle.cdc.mining.RedoLogFile@216a4111 and io.confluent.connect.oracle.cdc.mining.RedoLogFile@71af15b8)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:423)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:368)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.retry(OracleDatabase.java:564)
#         at io.confluent.connect.oracle.cdc.OracleRedoLogReader.readRedoLogs(OracleRedoLogReader.java:89)
#         ... 5 more
# Caused by: java.lang.IllegalStateException: Duplicate key 1_7_1088159216.dbf (attempted merging values io.confluent.connect.oracle.cdc.mining.RedoLogFile@216a4111 and io.confluent.connect.oracle.cdc.mining.RedoLogFile@71af15b8)
#         at java.base/java.util.stream.Collectors.duplicateKeyException(Collectors.java:133)
#         at java.base/java.util.stream.Collectors.lambda$uniqKeysMapAccumulator$1(Collectors.java:180)
#         at java.base/java.util.stream.ReduceOps$3ReducingSink.accept(ReduceOps.java:169)
#         at java.base/java.util.ArrayList$ArrayListSpliterator.forEachRemaining(ArrayList.java:1655)
#         at java.base/java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:484)
#         at java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:474)
#         at java.base/java.util.stream.ReduceOps$ReduceOp.evaluateSequential(ReduceOps.java:913)
#         at java.base/java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)
#         at java.base/java.util.stream.ReferencePipeline.collect(ReferencePipeline.java:578)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.updateArchiveFileList(WithoutContinuousMining.java:410)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.startFrom(WithoutContinuousMining.java:128)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.mineRedoLogs(WithoutContinuousMining.java:82)
#         at io.confluent.connect.oracle.cdc.OracleRedoLogReader.lambda$readRedoLogs$0(OracleRedoLogReader.java:91)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         ... 8 more

log "Waiting 60s for connector to read new data"
sleep 60

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

log "🚚 If you're planning to inject more data, have a look at https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-cdc-oracle19-source/README.md#note-on-redologrowfetchsize"
