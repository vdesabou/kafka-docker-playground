#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-105303-oracle-cdc-not-writing-records-after-snapshot-when-using-avro-serializers.yml"

# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
log "⌛ Waiting up to $MAX_WAIT seconds for Oracle DB to start"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "04_populate_customer.sh" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     logerror "ERROR: The logs in oracle container do not show '04_populate_customer.sh' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
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
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "oracle.server": "oracle",
               "oracle.port": 1521,
               "oracle.sid": "XE",
               "oracle.username": "MYUSER",
               "oracle.password": "password",
               "start.from":"snapshot",
               "redo.log.topic.name": "redo-log-topic",
               "redo.log.consumer.bootstrap.servers":"broker:9092",
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1
          }' \
     http://localhost:8083/connectors/cdc-oracle11-source/config | jq .

log "Waiting 10s for connector to read existing data"
sleep 10

log
docker exec -i oracle bash -c "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe && /u01/app/oracle/product/11.2.0/xe/bin/sqlplus MYUSER/password@//localhost:1521/XE" << EOF
  INSERT INTO CUSTOMERS ( XREG_DISTRIBUIDO, XDESCRIPCION, XSUBTIPO_CLASE, XSUBTIPO_ID, XFECHA_ALTA, XFECHA_MODIF, XUSUARIO_ALTA, XUSUARIO_MODIF) VALUES ('1','Prueba RRR','1','P_RR6',sysdate,'','Vincent','Vincent');
  exit;
EOF

log "Waiting 60s for connector to read new data"
sleep 60

log "Verifying topic XE.MYUSER.CUSTOMERS: there should be 6 records"
set +e
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic XE.MYUSER.CUSTOMERS --from-beginning --max-messages 6 > /tmp/result.log  2>&1
set -e
cat /tmp/result.log

log "Verifying topic redo-log-topic: there should be 1 records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic redo-log-topic --from-beginning --max-messages 1

# with 2.0.2:

# [2022-05-12 04:45:48,535] ERROR [cdc-oracle11-source|task-0] WorkerSourceTask{id=cdc-oracle11-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Error while polling for records
# 	at io.confluent.connect.oracle.cdc.util.RecordQueue.poll(RecordQueue.java:372)
# 	at io.confluent.connect.oracle.cdc.OracleCdcSourceTask.poll(OracleCdcSourceTask.java:500)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:307)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:263)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 32768 to read redo log from jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle)(PORT=1521))(CONNECT_DATA=(SID=XE))) with user 'MYUSER' (pool=oracle-cdc-source:cdc-oracle11-source-0): ORA-01292: no log file has been specified for the current LogMiner session
# ORA-06512: at "SYS.DBMS_LOGMNR", line 58
# ORA-06512: at line 1

# 	at io.confluent.connect.oracle.cdc.OracleRedoLogReader.readRedoLogs(OracleRedoLogReader.java:108)
# 	at io.confluent.connect.oracle.cdc.util.RecordQueue.lambda$createLoggingSupplier$0(RecordQueue.java:465)
# 	at java.base/java.util.concurrent.CompletableFuture$AsyncSupply.run(CompletableFuture.java:1700)
# 	... 3 more
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed on attempt 1 of 32768 to read redo log from jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle)(PORT=1521))(CONNECT_DATA=(SID=XE))) with user 'MYUSER' (pool=oracle-cdc-source:cdc-oracle11-source-0): ORA-01292: no log file has been specified for the current LogMiner session
# ORA-06512: at "SYS.DBMS_LOGMNR", line 58
# ORA-06512: at line 1

# 	at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:423)
# 	at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:368)
# 	at io.confluent.connect.oracle.cdc.OracleDatabase.retry(OracleDatabase.java:569)
# 	at io.confluent.connect.oracle.cdc.OracleRedoLogReader.readRedoLogs(OracleRedoLogReader.java:92)
# 	... 5 more
# Caused by: java.sql.SQLException: ORA-01292: no log file has been specified for the current LogMiner session
# ORA-06512: at "SYS.DBMS_LOGMNR", line 58
# ORA-06512: at line 1

# 	at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:509)
# 	at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:461)
# 	at oracle.jdbc.driver.T4C8Oall.processError(T4C8Oall.java:1104)
# 	at oracle.jdbc.driver.T4CTTIfun.receive(T4CTTIfun.java:550)
# 	at oracle.jdbc.driver.T4CTTIfun.doRPC(T4CTTIfun.java:268)
# 	at oracle.jdbc.driver.T4C8Oall.doOALL(T4C8Oall.java:655)
# 	at oracle.jdbc.driver.T4CStatement.doOall8(T4CStatement.java:229)
# 	at oracle.jdbc.driver.T4CStatement.doOall8(T4CStatement.java:41)
# 	at oracle.jdbc.driver.T4CStatement.executeForRows(T4CStatement.java:928)
# 	at oracle.jdbc.driver.OracleStatement.doExecuteWithTimeout(OracleStatement.java:1205)
# 	at oracle.jdbc.driver.OracleStatement.executeUpdateInternal(OracleStatement.java:1747)
# 	at oracle.jdbc.driver.OracleStatement.executeLargeUpdate(OracleStatement.java:1712)
# 	at oracle.jdbc.driver.OracleStatement.executeUpdate(OracleStatement.java:1699)
# 	at oracle.jdbc.driver.OracleStatementWrapper.executeUpdate(OracleStatementWrapper.java:285)
# 	at oracle.ucp.jdbc.proxy.oracle$1ucp$1jdbc$1proxy$1oracle$1StatementProxy$2oracle$1jdbc$1internal$1OracleStatement$$$Proxy.executeUpdate(Unknown Source)
# 	at io.confluent.connect.oracle.cdc.logging.LogUtils.executeUpdate(LogUtils.java:30)
# 	at io.confluent.connect.oracle.cdc.OracleDatabase.executeUpdate(OracleDatabase.java:1017)
# 	at io.confluent.connect.oracle.cdc.OracleDatabase.startLogMinerSession(OracleDatabase.java:449)
# 	at io.confluent.connect.oracle.cdc.OracleDatabase.startLogMinerSessionContinuousMine(OracleDatabase.java:419)
# 	at io.confluent.connect.oracle.cdc.mining.WithContinuousMining.mineRedoLogs(WithContinuousMining.java:66)
# 	at io.confluent.connect.oracle.cdc.OracleRedoLogReader.lambda$readRedoLogs$0(OracleRedoLogReader.java:94)
# 	at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
# 	... 8 more
# Caused by: Error : 1292, Position : 0, Sql = BEGIN DBMS_LOGMNR.START_LOGMNR(STARTSCN => 329843, OPTIONS => DBMS_LOGMNR.DICT_FROM_ONLINE_CATALOG + DBMS_LOGMNR.CONTINUOUS_MINE + DBMS_LOGMNR.SKIP_CORRUPTION); END;, OriginalSql = {CALL DBMS_LOGMNR.START_LOGMNR(STARTSCN => 329843, OPTIONS => DBMS_LOGMNR.DICT_FROM_ONLINE_CATALOG + DBMS_LOGMNR.CONTINUOUS_MINE + DBMS_LOGMNR.SKIP_CORRUPTION)}, Error Msg = ORA-01292: no log file has been specified for the current LogMiner session
# ORA-06512: at "SYS.DBMS_LOGMNR", line 58
# ORA-06512: at line 1

# 	at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:513)
# 	... 29 more