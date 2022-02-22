#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

create_or_get_oracle_image "LINUX.X64_193000_db_home.zip" "$(pwd)/ora-setup-scripts-cdb-table"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.cdb-table.repro-88665-cold-backup.yml"


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
               "table.inclusion.regex": ".*CUSTOMERS.*",
               "table.topic.name.template": "${databaseName}.${schemaName}.${tableName}",
               "numeric.mapping": "best_fit",
               "connection.pool.max.size": 20,
               "redo.log.row.fetch.size":1,
               "oracle.dictionary.mode": "online"
          }' \
     http://localhost:8083/connectors/cdc-oracle-source-cdb/config | jq .

log "Waiting 60s for connector to read existing data"
sleep 60

log "Running SQL scripts"
for script in ${DIR}/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

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

# log "Pausing connector"
# curl --request PUT \
#   --url http://localhost:8083/connectors/cdc-oracle-source-cdb/pause

log "Adding connect catalog user"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA

CREATE USER C##reco_cat IDENTIFIED BY mypassword DEFAULT TABLESPACE USERS;
ALTER USER C##reco_cat QUOTA UNLIMITED ON USERS;

grant create session to C##reco_cat;
grant recovery_catalog_owner to C##reco_cat;
exit;
EOF

log "Adding connect catalog to RMAN"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;rman target /" << EOF
connect catalog C##reco_cat/mypassword
create catalog;
register database;
  exit;
EOF

log "SHUTDOWN IMMEDIATE and STARTUP MOUNT"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA

SHUTDOWN IMMEDIATE
STARTUP MOUNT
exit;
EOF

docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;rman target /" << EOF
CONFIGURE SNAPSHOT CONTROLFILE NAME TO '{Path for Snapshot file}.f'; # default
EOF

# https://www.carajandb.com/en/blog/2019/backup-and-recovery-with-rman-is-easy/
set +e
log "Doing a cold backup using RMAN"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;rman target /" << EOF
connect catalog C##reco_cat/mypassword
BACKUP INCREMENTAL LEVEL=0 DATABASE tag playground; 
EOF
set -e

# docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;rman target /" << EOF
# connect catalog C##reco_cat/mypassword
# SHOW ALL;
# sql 'alter system archive log current ';
# delete archivelog all;
# YES
#   exit;
# EOF

log "ALTER DATABASE OPEN"
docker exec -i oracle bash -c "ORACLE_SID=ORCLCDB;export ORACLE_SID;sqlplus /nolog" << EOF
CONNECT sys/Admin123 AS SYSDBA

alter database open;
exit;
EOF

# if we don't call alter database open, we get:

# [2022-02-14 17:02:49,745] ERROR [cdc-oracle-source-cdb|worker|reconfig] Reconfiguration check background thread threw exception (io.confluent.connect.oracle.cdc.OracleCdcSourceConnector:605)
# org.apache.kafka.connect.errors.ConnectException: Failed on 1st attempt to read tables from jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle)(PORT=1521))(CONNECT_DATA=(SID=ORCLCDB))) with user 'C##MYUSER' (pool=oracle-cdc-source:cdc-oracle-source-cdb): Exception occurred while getting connection: oracle.ucp.UniversalConnectionPoolException: Cannot get Connection from Datasource: java.sql.SQLRecoverableException: ORA-01033: ORACLE initialization or shutdown in progress

#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:423)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:368)
#         at io.confluent.connect.oracle.cdc.OracleDatabase.readAccessibleTables(OracleDatabase.java:662)
#         at io.confluent.connect.oracle.cdc.OracleCdcSourceConnector.reconfigCheckTask(OracleCdcSourceConnector.java:509)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.runAndReset(FutureTask.java:305)
#         at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:305)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.sql.SQLException: Exception occurred while getting connection: oracle.ucp.UniversalConnectionPoolException: Cannot get Connection from Datasource: java.sql.SQLRecoverableException: ORA-01033: ORACLE initialization or shutdown in progress

#         at oracle.ucp.util.UCPErrorHandler.newSQLException(UCPErrorHandler.java:456)
#         at oracle.ucp.util.UCPErrorHandler.throwSQLException(UCPErrorHandler.java:133)
#         at oracle.ucp.jdbc.PoolDataSourceImpl.getConnection(PoolDataSourceImpl.java:2004)
#         at oracle.ucp.jdbc.PoolDataSourceImpl.access$400(PoolDataSourceImpl.java:201)
#         at oracle.ucp.jdbc.PoolDataSourceImpl$31.build(PoolDataSourceImpl.java:4279)
#         at oracle.ucp.jdbc.PoolDataSourceImpl.getConnection(PoolDataSourceImpl.java:1917)
#         at oracle.ucp.jdbc.PoolDataSourceImpl.getConnection(PoolDataSourceImpl.java:1880)
#         at oracle.ucp.jdbc.PoolDataSourceImpl.getConnection(PoolDataSourceImpl.java:1865)
#         at io.confluent.connect.oracle.cdc.connection.SharedConnectionPool.connection(SharedConnectionPool.java:199)
#         at io.confluent.connect.oracle.cdc.connection.ConnectionPoolHandle.connection(ConnectionPoolHandle.java:65)
#         at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:410)
#         ... 9 more
# Caused by: oracle.ucp.UniversalConnectionPoolException: Cannot get Connection from Datasource: java.sql.SQLRecoverableException: ORA-01033: ORACLE initialization or shutdown in progress

#         at oracle.ucp.util.UCPErrorHandler.newUniversalConnectionPoolException(UCPErrorHandler.java:336)
#         at oracle.ucp.util.UCPErrorHandler.throwUniversalConnectionPoolException(UCPErrorHandler.java:59)
#         at oracle.ucp.jdbc.oracle.OracleDataSourceConnectionFactoryAdapter.createConnection(OracleDataSourceConnectionFactoryAdapter.java:134)
#         at oracle.ucp.common.Database.createPooledConnection(Database.java:256)
#         at oracle.ucp.common.Service$2.exec(Service.java:630)
#         at oracle.ucp.common.Service$2.exec(Service.java:627)
#         at oracle.ucp.actors.InterruptableActor.doAction(InterruptableActor.java:128)
#         at oracle.ucp.common.Service.createConnectionInterruptably(Service.java:627)
#         at oracle.ucp.common.Service.create(Service.java:807)
#         at oracle.ucp.common.Service.create(Service.java:575)
#         at oracle.ucp.common.Topology.create(Topology.java:159)
#         at oracle.ucp.common.Core.growBorrowed(Core.java:1057)
#         at oracle.ucp.common.UniversalConnectionPoolImpl.helpGrowBorrowed(UniversalConnectionPoolImpl.java:301)
#         at oracle.ucp.common.UniversalConnectionPoolImpl.borrowConnectionWithoutCountingRequests(UniversalConnectionPoolImpl.java:247)
#         at oracle.ucp.common.UniversalConnectionPoolImpl.borrowConnectionAndValidate(UniversalConnectionPoolImpl.java:153)
#         at oracle.ucp.common.UniversalConnectionPoolImpl.borrowConnection(UniversalConnectionPoolImpl.java:122)
#         at oracle.ucp.jdbc.JDBCConnectionPool.borrowConnection(JDBCConnectionPool.java:174)
#         at oracle.ucp.jdbc.oracle.OracleJDBCConnectionPool.borrowConnection(OracleJDBCConnectionPool.java:613)
#         at oracle.ucp.jdbc.oracle.OracleConnectionConnectionPool.borrowConnection(OracleConnectionConnectionPool.java:103)
#         at oracle.ucp.jdbc.PoolDataSourceImpl.getConnection(PoolDataSourceImpl.java:1981)
#         ... 17 more
# Caused by: java.sql.SQLRecoverableException: ORA-01033: ORACLE initialization or shutdown in progress

#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:509)
#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:456)
#         at oracle.jdbc.driver.T4CTTIoer11.processError(T4CTTIoer11.java:451)
#         at oracle.jdbc.driver.T4CTTIoauthenticate.processError(T4CTTIoauthenticate.java:548)
#         at oracle.jdbc.driver.T4CTTIfun.receive(T4CTTIfun.java:550)
#         at oracle.jdbc.driver.T4CTTIfun.doRPC(T4CTTIfun.java:268)
#         at oracle.jdbc.driver.T4CTTIoauthenticate.doOSESSKEY(T4CTTIoauthenticate.java:521)
#         at oracle.jdbc.driver.T4CConnection.logon(T4CConnection.java:691)
#         at oracle.jdbc.driver.PhysicalConnection.connect(PhysicalConnection.java:793)
#         at oracle.jdbc.driver.T4CDriverExtension.getConnection(T4CDriverExtension.java:57)
#         at oracle.jdbc.driver.OracleDriver.connect(OracleDriver.java:747)
#         at oracle.jdbc.pool.OracleDataSource.getPhysicalConnection(OracleDataSource.java:406)
#         at oracle.jdbc.pool.OracleDataSource.getConnection(OracleDataSource.java:291)
#         at oracle.jdbc.pool.OracleDataSource$1.build(OracleDataSource.java:1683)
#         at oracle.jdbc.pool.OracleDataSource$1.build(OracleDataSource.java:1669)
#         at oracle.ucp.jdbc.oracle.OracleDataSourceConnectionFactoryAdapter.createConnection(OracleDataSourceConnectionFactoryAdapter.java:103)
#         ... 34 more

sleep 20

# log "restart failed task"
# curl --request POST \
#   --url 'http://localhost:8083/connectors/cdc-oracle-source-cdb/restart?includeTasks=true&onlyFailed=true'


#curl --request POST --url http://localhost:8083/connectors/cdc-oracle-source-cdb/tasks/0/restart

sleep 10

log "Running SQL scripts"
for script in ${DIR}/sample-sql-scripts/*.sh
do
     $script "ORCLCDB"
done

log "Waiting 60s for connector to read new data"
sleep 60

log "Verifying topic ORCLCDB.C__MYUSER.CUSTOMERS: there should be 24 records"
set +e
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic ORCLCDB.C__MYUSER.CUSTOMERS --from-beginning --max-messages 24 > /tmp/result.log  2>&1
set -e
cat /tmp/result.log
