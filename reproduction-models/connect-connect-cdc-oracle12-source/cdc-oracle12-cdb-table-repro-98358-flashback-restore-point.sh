#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "linuxx64_12201_database.zip" "../../connect/connect-cdc-oracle12-source/ora-setup-scripts-cdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-98358-flashback-restore-point.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
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
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select current_scn from v\$database;
create restore point CLEAN_DB guarantee flashback database;
exit;
EOF

# SQL> 
# CURRENT_SCN
# -----------
#     1446910

# Create a redo-log-topic. Please make sure you create a topic with the same name you will use for "redo.log.topic.name": "redo-log-topic"
# CC-13104
docker exec broker kafka-topics --create --topic redo-log-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1 --config cleanup.policy=delete --config retention.ms=120960000
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
for script in ../../connect/connect-cdc-oracle12-source/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Waiting 20s for connector to read new data"
sleep 20

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS: there should be 13 records"
set +e
timeout 60 docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 13 > /tmp/result.log  2>&1
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
timeout 60 docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 9

log "Get SCN before Flashback"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select current_scn from v\$database;
exit;
EOF

# CURRENT_SCN
# -----------
#     1447201

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
#     1447937

sleep 10

log "restart failed task"
curl --request POST \
  --url 'http://localhost:8083/connectors/cdc-oracle-source-cdb/restart?includeTasks=true&onlyFailed=true'

exit 0
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


     #  "tasks": [
     #    {
     #      "id": 0,
     #      "state": "RUNNING",
     #      "worker_id": "connect:8083"
     #    },
     #    {
     #      "id": 1,
     #      "state": "RUNNING",
     #      "worker_id": "connect:8083"
     #    }
     #  ],

log "Getting redo log files"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA
select FIRST_CHANGE#,NEXT_CHANGE# from v\$ARCHIVED_LOG;
  exit;
EOF

# SQL> 
# FIRST_CHANGE# NEXT_CHANGE#
# ------------- ------------
#       2147061      2159261
#       2159261      2160515
#       2160515      2160531
#       2160531      2161253
#       2160531      2161253
#       2161253      2162885
#       2160515      2160531

# 7 rows selected.

# Not available
# ---> STARTSCN => 2162885, ENDSCN => 2160629

log "Restart connector with force_current"
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
               "start.from":"force_current",
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
for script in ../../connect/connect-cdc-oracle12-source/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

# [2022-03-24 14:07:50,992] WARN [cdc-oracle-source-cdb|task-0|redoLog] Failed to add archived log files. (io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining:434)
# java.sql.SQLException: ORA-01289: cannot add duplicate logfile /home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_10_k3rypdhk_.arc
# ORA-06512: at "SYS.DBMS_LOGMNR", line 82
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
#         at io.confluent.connect.oracle.cdc.OracleDatabase.addArchivedLogFiles(OracleDatabase.java:901)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.addArchivedFiles(WithoutContinuousMining.java:432)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.startFrom(WithoutContinuousMining.java:168)
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
# Caused by: Error : 1289, Position : 0, Sql = BEGIN DBMS_LOGMNR.ADD_LOGFILE(LOGFILENAME => '/home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_10_k3rypdhk_.arc', OPTIONS => DBMS_LOGMNR.ADDFILE); END;, OriginalSql = {CALL DBMS_LOGMNR.ADD_LOGFILE(LOGFILENAME => '/home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_10_k3rypdhk_.arc', OPTIONS => DBMS_LOGMNR.ADDFILE)}, Error Msg = ORA-01289: cannot add duplicate logfile /home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_10_k3rypdhk_.arc

# getting ORA-01287 when doing a force_current
# https://onlineappsdba.com/index.php/2009/09/11/oracle-database-incarnation-open-resetlogs-scn/
# [2022-03-24 13:51:54,321] ERROR [cdc-oracle-source-cdb|task-0|redoLog] SQL exception:  (io.confluent.connect.oracle.cdc.logging.LogUtils:32)
# java.sql.SQLException: ORA-01287: file /home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_7_k3rxmkkg_.arc is from a different database incarnation
# ORA-06512: at "SYS.DBMS_LOGMNR", line 82
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
#         at io.confluent.connect.oracle.cdc.OracleDatabase.addArchivedLogFiles(OracleDatabase.java:901)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.addArchivedFiles(WithoutContinuousMining.java:432)
#         at io.confluent.connect.oracle.cdc.mining.WithoutContinuousMining.startFrom(WithoutContinuousMining.java:168)
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
# Caused by: Error : 1287, Position : 0, Sql = BEGIN DBMS_LOGMNR.ADD_LOGFILE(LOGFILENAME => '/home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_7_k3rxmkkg_.arc', OPTIONS => DBMS_LOGMNR.ADDFILE); END;, OriginalSql = {CALL DBMS_LOGMNR.ADD_LOGFILE(LOGFILENAME => '/home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_7_k3rxmkkg_.arc', OPTIONS => DBMS_LOGMNR.ADDFILE)}, Error Msg = ORA-01287: file /home/oracle/db_recovery_file_dest/ORCLCDB/archivelog/2022_03_24/o1_mf_1_7_k3rxmkkg_.arc is from a different database incarnation
# ORA-06512: at "SYS.DBMS_LOGMNR", line 82
# ORA-06512: at line 1

#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:513)
#         ... 30 more

# let it run and SCN will be catch up, but then it will reprocess already handled data:
     #   {
     #      "id": 1,
     #      "state": "FAILED",
     #      "worker_id": "connect:8083",
     #      "trace": "org.apache.kafka.connect.errors.ConnectException: Error while polling for records\n\tat io.confluent.connect.oracle.cdc.util.RecordQueue.poll(RecordQueue.java:372)\n\tat io.confluent.connect.oracle.cdc.OracleCdcSourceTask.poll(OracleCdcSourceTask.java:493)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:308)\n\tat org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)\n\tat org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)\n\tat org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: org.apache.kafka.connect.errors.ConnectException: Exception converting redo to change event. SQL: '  alter table CUSTOMERS add (\n    country VARCHAR(50)\n  );' INFO: USER DDL (PlSql=0 RecDep=0)\n\tat io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:343)\n\tat io.confluent.connect.oracle.cdc.ChangeEventGenerator.processSingleRecord(ChangeEventGenerator.java:496)\n\tat io.confluent.connect.oracle.cdc.ChangeEventGenerator.lambda$doGenerateChangeEvent$2(ChangeEventGenerator.java:419)\n\tat java.base/java.util.stream.ReferencePipeline$3$1.accept(ReferencePipeline.java:195)\n\tat java.base/java.util.Spliterators$ArraySpliterator.forEachRemaining(Spliterators.java:948)\n\tat java.base/java.util.stream.AbstractPipeline.copyInto(AbstractPipeline.java:484)\n\tat java.base/java.util.stream.AbstractPipeline.wrapAndCopyInto(AbstractPipeline.java:474)\n\tat java.base/java.util.stream.ReduceOps$ReduceOp.evaluateSequential(ReduceOps.java:913)\n\tat java.base/java.util.stream.AbstractPipeline.evaluate(AbstractPipeline.java:234)\n\tat java.base/java.util.stream.ReferencePipeline.collect(ReferencePipeline.java:578)\n\tat io.confluent.connect.oracle.cdc.ChangeEventGenerator.doGenerateChangeEvent(ChangeEventGenerator.java:421)\n\tat io.confluent.connect.oracle.cdc.ChangeEventGenerator.execute(ChangeEventGenerator.java:221)\n\tat io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)\n\tat java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)\n\t... 3 more\nCaused by: org.apache.kafka.connect.errors.SchemaBuilderException: Cannot create field because of field name duplication COUNTRY\n\tat org.apache.kafka.connect.data.SchemaBuilder.field(SchemaBuilder.java:330)\n\tat io.confluent.connect.oracle.cdc.OracleDdlParser.parseAndApply(OracleDdlParser.java:250)\n\tat io.confluent.connect.oracle.cdc.record.OracleChangeEventSourceRecordConverter.convert(OracleChangeEventSourceRecordConverter.java:318)\n\t... 16 more\n"
     #    }