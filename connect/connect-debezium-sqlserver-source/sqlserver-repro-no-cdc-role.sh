#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Load ./repro-no-cdc-role/inventory.sql to SQL Server"
cat ./repro-no-cdc-role/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Verify that vincent has no cdc permission, it should be empty"
cat ./repro-no-cdc-role/verify-cdc-access.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U vincent -P Password!'

log "Creating Debezium SQL Server source connector, using vincent"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
              "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
              "tasks.max": "1",
              "database.hostname": "sqlserver",
              "database.port": "1433",
              "database.user": "vincent",
              "database.password": "Password!",
              "database.server.name": "server1",
              "database.dbname" : "testDB",
              "database.history.kafka.bootstrap.servers": "broker:9092",
              "database.history.kafka.topic": "schema-changes.inventory"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

log "Connector status"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .


docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas','pam@office.com');
GO
EOF

sleep 5

log "Connector status"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5

# {
#   "name": "debezium-sqlserver-source",
#   "connector": {
#     "state": "RUNNING",
#     "worker_id": "connect:8083"
#   },
#   "tasks": [
#     {
#       "id": 0,
#       "state": "FAILED",
#       "worker_id": "connect:8083",
#       "trace": "org.apache.kafka.connect.errors.ConnectException: An exception occurred in the change event producer. This connector will be stopped.\n\tat io.debezium.pipeline.ErrorHandler.setProducerThrowable(ErrorHandler.java:42)\n\tat io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:291)\n\tat io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:59)\n\tat io.debezium.pipeline.ChangeEventSourceCoordinator.streamEvents(ChangeEventSourceCoordinator.java:159)\n\tat io.debezium.pipeline.ChangeEventSourceCoordinator.lambda$start$0(ChangeEventSourceCoordinator.java:122)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: com.microsoft.sqlserver.jdbc.SQLServerException: The SELECT permission was denied on the object 'change_tables', database 'testDB', schema 'cdc'.\n\tat com.microsoft.sqlserver.jdbc.SQLServerException.makeFromDatabaseError(SQLServerException.java:262)\n\tat com.microsoft.sqlserver.jdbc.SQLServerStatement.getNextResult(SQLServerStatement.java:1621)\n\tat com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.doExecutePreparedStatement(SQLServerPreparedStatement.java:592)\n\tat com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement$PrepStmtExecCmd.doExecute(SQLServerPreparedStatement.java:522)\n\tat com.microsoft.sqlserver.jdbc.TDSCommand.execute(IOBuffer.java:7194)\n\tat com.microsoft.sqlserver.jdbc.SQLServerConnection.executeCommand(SQLServerConnection.java:2935)\n\tat com.microsoft.sqlserver.jdbc.SQLServerStatement.executeCommand(SQLServerStatement.java:248)\n\tat com.microsoft.sqlserver.jdbc.SQLServerStatement.executeStatement(SQLServerStatement.java:223)\n\tat com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.executeQuery(SQLServerPreparedStatement.java:444)\n\tat io.debezium.jdbc.JdbcConnection.prepareQueryAndMap(JdbcConnection.java:745)\n\tat io.debezium.connector.sqlserver.SqlServerConnection.listOfNewChangeTables(SqlServerConnection.java:387)\n\tat io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:159)\n\t... 8 more\n"
#     }
#   ],
#   "type": "source"
# }

# 2021-07-15 15:54:58,559] WARN No table has enabled CDC or security constraints prevents getting the list of change tables (io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource)
# [2021-07-15 15:54:58,559] WARN No whitelisted table has enabled CDC, whitelisted table list does not contain any table with CDC enabled or no table match the white/blacklist filter(s) (io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource)
# [2021-07-15 15:54:58,559] INFO Last position recorded in offsets is 00000025:00000440:0003(NULL)[1] (io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource)
# [2021-07-15 15:55:10,753] ERROR Producer failure (io.debezium.pipeline.ErrorHandler)
# com.microsoft.sqlserver.jdbc.SQLServerException: The SELECT permission was denied on the object 'change_tables', database 'testDB', schema 'cdc'.
#         at com.microsoft.sqlserver.jdbc.SQLServerException.makeFromDatabaseError(SQLServerException.java:262)
#         at com.microsoft.sqlserver.jdbc.SQLServerStatement.getNextResult(SQLServerStatement.java:1621)
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.doExecutePreparedStatement(SQLServerPreparedStatement.java:592)
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement$PrepStmtExecCmd.doExecute(SQLServerPreparedStatement.java:522)
#         at com.microsoft.sqlserver.jdbc.TDSCommand.execute(IOBuffer.java:7194)
#         at com.microsoft.sqlserver.jdbc.SQLServerConnection.executeCommand(SQLServerConnection.java:2935)
#         at com.microsoft.sqlserver.jdbc.SQLServerStatement.executeCommand(SQLServerStatement.java:248)
#         at com.microsoft.sqlserver.jdbc.SQLServerStatement.executeStatement(SQLServerStatement.java:223)
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.executeQuery(SQLServerPreparedStatement.java:444)
#         at io.debezium.jdbc.JdbcConnection.prepareQueryAndMap(JdbcConnection.java:745)
#         at io.debezium.connector.sqlserver.SqlServerConnection.listOfNewChangeTables(SqlServerConnection.java:387)
#         at io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:159)
#         at io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:59)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.streamEvents(ChangeEventSourceCoordinator.java:159)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.lambda$start$0(ChangeEventSourceCoordinator.java:122)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2021-07-15 15:55:10,755] INFO Finished streaming (io.debezium.pipeline.ChangeEventSourceCoordinator)
# [2021-07-15 15:55:10,755] INFO Connected metrics set to 'false' (io.debezium.pipeline.metrics.StreamingChangeEventSourceMetrics)
# [2021-07-15 15:55:10,922] INFO WorkerSourceTask{id=debezium-sqlserver-source-0} flushing 0 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask)
# [2021-07-15 15:55:10,922] ERROR WorkerSourceTask{id=debezium-sqlserver-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: An exception occurred in the change event producer. This connector will be stopped.
#         at io.debezium.pipeline.ErrorHandler.setProducerThrowable(ErrorHandler.java:42)
#         at io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:291)
#         at io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:59)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.streamEvents(ChangeEventSourceCoordinator.java:159)
#         at io.debezium.pipeline.ChangeEventSourceCoordinator.lambda$start$0(ChangeEventSourceCoordinator.java:122)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.microsoft.sqlserver.jdbc.SQLServerException: The SELECT permission was denied on the object 'change_tables', database 'testDB', schema 'cdc'.
#         at com.microsoft.sqlserver.jdbc.SQLServerException.makeFromDatabaseError(SQLServerException.java:262)
#         at com.microsoft.sqlserver.jdbc.SQLServerStatement.getNextResult(SQLServerStatement.java:1621)
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.doExecutePreparedStatement(SQLServerPreparedStatement.java:592)
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement$PrepStmtExecCmd.doExecute(SQLServerPreparedStatement.java:522)
#         at com.microsoft.sqlserver.jdbc.TDSCommand.execute(IOBuffer.java:7194)
#         at com.microsoft.sqlserver.jdbc.SQLServerConnection.executeCommand(SQLServerConnection.java:2935)
#         at com.microsoft.sqlserver.jdbc.SQLServerStatement.executeCommand(SQLServerStatement.java:248)
#         at com.microsoft.sqlserver.jdbc.SQLServerStatement.executeStatement(SQLServerStatement.java:223)
#         at com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.executeQuery(SQLServerPreparedStatement.java:444)
#         at io.debezium.jdbc.JdbcConnection.prepareQueryAndMap(JdbcConnection.java:745)
#         at io.debezium.connector.sqlserver.SqlServerConnection.listOfNewChangeTables(SqlServerConnection.java:387)
#         at io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:159)
#         ... 8 more
# [2021-07-15 15:55:10,923] INFO Stopping down connector (io.debezium.connector.common.BaseSourceTask)