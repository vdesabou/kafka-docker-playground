#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "../../connect/connect-cdc-oracle19-source/ora-setup-scripts-cdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-98358-flashback-restore-point.yml"


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
sleep 10

log "Enable FLASHBACK ON"
docker exec -i oracle bash -c "mkdir -p /home/oracle/db_recovery_file_dest;ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
alter system set db_recovery_file_dest_size='2G';
alter system set db_recovery_file_dest='/home/oracle/db_recovery_file_dest';
ALTER DATABASE FLASHBACK ON;
exit;
EOF

# https://www.datavail.com/blog/oracle-rman-backup-and-recovery-with-restore-points/
log "Create a restore point"
docker exec -i oracle bash -c "mkdir -p /home/oracle/db_recovery_file_dest;ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select current_scn from v\$database;
create restore point CLEAN_DB guarantee flashback database;
exit;
EOF

# CURRENT_SCN
# -----------
#     2158954

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

log "Waiting 20s for connector to read existing data"
sleep 20

log "Running SQL scripts"
for script in ../../connect/connect-cdc-oracle19-source/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Waiting 20s for connector to read new data"
sleep 20

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

log "Get SCN before Flashback"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select current_scn from v\$database;
exit;
EOF

# CURRENT_SCN
# -----------
#     2161373

log "Make sure FLASHBACK is ON"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select FLASHBACK_ON from V\$DATABASE;
-- SELECT Parameter,Value FROM V\$OPTION Where Value = 'TRUE';
exit;
EOF

# https://www.datavail.com/blog/oracle-rman-backup-and-recovery-with-restore-points/
log "Rewinding a Database with Flashback Database"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select current_scn from v\$database;
shutdown immediate;
startup mount;
select * from v\$restore_point;
flashback database to restore point CLEAN_DB;
alter database open resetlogs;
select current_scn from v\$database;
exit;
EOF

# SQL> 
# CURRENT_SCN
# -----------
#     2159345

log "restart failed task"
curl --request POST \
  --url 'http://localhost:8083/connectors/cdc-oracle-source-cdb/restart?includeTasks=true&onlyFailed=true'


#curl --request POST --url http://localhost:8083/connectors/cdc-oracle-source-cdb/tasks/0/restart

# [2022-03-24 12:53:19,480] WARN [cdc-oracle-source-cdb|task-0|redoLog] Failed to open LogMiner session with error. (io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining:531)
# java.sql.SQLException: ORA-01281: SCN range specified is invalid
# ORA-06512: at "SYS.DBMS_LOGMNR", line 72
# ORA-06512: at line 1

#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:509)
#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:461)
#         at oracle.jdbc.driver.T4C8Oall.processError(T4C8Oall.java:1104)
#         at oracle.jdbc.driver.T4CTTIfun.receive(T4CTTIfun.java:550)
#         at oracle.jdbc.driver.T4CTTIfun.doRPC(T4CTTIfun.java:268)
#         at oracle.jdbc.driver.T4C8Oall.doOALL(T4C8Oall.java:655)
#         at oracle.jdbc.driver.T4CStatement.doOall8(T4CStatement.java:229)
#         at oracle.jdbc.driver.T4CStatement.doOall8(T4CStatement.java:41)
#         at oracle.jdbc.driver.T4CStatement.executeForRows(T4CStatement.java:928)
#         at oracle.jdbc.driver.OracleStatement.doExecuteWithTimeout(OracleStatement.java:1205)
#         at oracle.jdbc.driver.OracleStatement.executeUpdateInternal(OracleStatement.java:1747)
#         at oracle.jdbc.driver.OracleStatement.executeLargeUpdate(OracleStatement.java:1712)
#         at oracle.jdbc.driver.OracleStatement.executeUpdate(OracleStatement.java:1699)
#         at oracle.jdbc.driver.OracleStatementWrapper.executeUpdate(OracleStatementWrapper.java:285)
#         at oracle.ucp.jdbc.proxy.oracle$1ucp$1jdbc$1proxy$1oracle$1StatementProxy$2oracle$1jdbc$1internal$1OracleStatement$$$Proxy.executeUpdate(Unknown Source)
#         at io.confluent.connect.oracle.cdc.logging.LogUtils.executeUpdate(LogUtils.java:30)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.executeUpdate(OracleDatabase.java:1010)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.startLogMinerSession(OracleDatabase.java:448)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.startLogMinerSessionMiningOnline(OracleDatabase.java:432)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.startSessionMiningOnline(WithoutContinuousMining.java:528)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.startFrom(WithoutContinuousMining.java:222)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.mineRedoLogs(WithoutContinuousMining.java:85)
#         at io.confluent.connect.oracle.cdc.OracleRedoLogReader.lambda$readRedoLogs$0(OracleRedoLogReader.java:95)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:368)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.retry(OracleDatabase.java:568)
#         at io.confluent.connect.oracle.cdc.OracleRedoLogReader.readRedoLogs(OracleRedoLogReader.java:93)
#         at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)
#         at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: Error : 1281, Position : 0, Sql = BEGIN DBMS_LOGMNR.START_LOGMNR(STARTSCN => 2162885, ENDSCN => 2160629, OPTIONS => DBMS_LOGMNR.DICT_FROM_ONLINE_CATALOG + DBMS_LOGMNR.SKIP_CORRUPTION); END;, OriginalSql = {CALL DBMS_LOGMNR.START_LOGMNR(STARTSCN => 2162885, ENDSCN => 2160629, OPTIONS => DBMS_LOGMNR.DICT_FROM_ONLINE_CATALOG + DBMS_LOGMNR.SKIP_CORRUPTION)}, Error Msg = ORA-01281: SCN range specified is invalid
# ORA-06512: at "SYS.DBMS_LOGMNR", line 72
# ORA-06512: at line 1

#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:513)
#         ... 31 more