#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Load ./repro-ff-5873/inventory.sql to SQL Server"
cat ./repro-ff-5873/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Creating Debezium SQL Server source connector"
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

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas','pam@office.com');
GO
EOF

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5

log "Drop role"
cat ./repro-ff-5873/drop-role.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

sleep 5

log "Connector status"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .


log "another insert"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas2','pam2@office.com');
GO
EOF

sleep 5

docker container logs connect | grep "The SELECT permission was denied"

log "Connector status"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .

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
#       "trace": "org.apache.kafka.connect.errors.ConnectException: An exception occurred in the change event producer. This connector will be stopped.\n\tat io.debezium.pipeline.ErrorHandler.setProducerThrowable(ErrorHandler.java:42)\n\tat io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:283)\n\tat io.debezium.pipeline.ChangeEventSourceCoordinator.streamEvents(ChangeEventSourceCoordinator.java:140)\n\tat io.debezium.pipeline.ChangeEventSourceCoordinator.lambda$start$0(ChangeEventSourceCoordinator.java:113)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)\n\tat java.base/java.lang.Thread.run(Thread.java:829)\nCaused by: com.microsoft.sqlserver.jdbc.SQLServerException: The SELECT permission was denied on the object 'change_tables', database 'testDB', schema 'cdc'.\n\tat com.microsoft.sqlserver.jdbc.SQLServerException.makeFromDatabaseError(SQLServerException.java:262)\n\tat com.microsoft.sqlserver.jdbc.SQLServerStatement.getNextResult(SQLServerStatement.java:1621)\n\tat com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.doExecutePreparedStatement(SQLServerPreparedStatement.java:592)\n\tat com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement$PrepStmtExecCmd.doExecute(SQLServerPreparedStatement.java:522)\n\tat com.microsoft.sqlserver.jdbc.TDSCommand.execute(IOBuffer.java:7194)\n\tat com.microsoft.sqlserver.jdbc.SQLServerConnection.executeCommand(SQLServerConnection.java:2935)\n\tat com.microsoft.sqlserver.jdbc.SQLServerStatement.executeCommand(SQLServerStatement.java:248)\n\tat com.microsoft.sqlserver.jdbc.SQLServerStatement.executeStatement(SQLServerStatement.java:223)\n\tat com.microsoft.sqlserver.jdbc.SQLServerPreparedStatement.executeQuery(SQLServerPreparedStatement.java:444)\n\tat io.debezium.jdbc.JdbcConnection.prepareQueryAndMap(JdbcConnection.java:740)\n\tat io.debezium.connector.sqlserver.SqlServerConnection.listOfNewChangeTables(SqlServerConnection.java:385)\n\tat io.debezium.connector.sqlserver.SqlServerStreamingChangeEventSource.execute(SqlServerStreamingChangeEventSource.java:153)\n\t... 7 more\n"
#     }
#   ],
#   "type": "source"
# }