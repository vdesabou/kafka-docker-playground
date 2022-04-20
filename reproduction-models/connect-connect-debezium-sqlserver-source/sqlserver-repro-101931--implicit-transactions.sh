#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-101931--implicit-transactions.yml"


log "Load inventory.sql to SQL Server"
cat inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Creating Debezium SQL Server source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
                    "tasks.max": "1",
                    "database.hostname": "sqlserver",
                    "database.port": "1433",
                    "database.user": "sa",
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
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas','pam2@office.com');
GO
EOF

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5


log "Printing sessions for Debezium (program_name=Microsoft JDBC Driver for SQL Server)"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

SET NOCOUNT ON

SELECT session_id,login_time,last_successful_logon,transaction_isolation_level,last_request_start_time,last_request_end_time
FROM sys.dm_exec_sessions
WHERE login_name = 'sa' and program_name='Microsoft JDBC Driver for SQL Server'
ORDER BY client_interface_name ASC

GO
EOF
cat /tmp/result.log

# session_id login_time              last_successful_logon   transaction_isolation_level last_request_start_time last_request_end_time  
# ---------- ----------------------- ----------------------- --------------------------- ----------------------- -----------------------
#         55 2022-04-20 10:14:27.307                    NULL                           2 2022-04-20 12:08:47.920 2022-04-20 12:08:47.920
#         61 2022-04-20 10:15:27.940                    NULL                           2 2022-04-20 12:08:27.920 2022-04-20 12:08:27.920

log "Printing connecttions for Debezium (program_name=Microsoft JDBC Driver for SQL Server)"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

SET NOCOUNT ON
SELECT sys.dm_exec_sessions.session_id,
       sys.dm_exec_sessions.program_name,
	   sys.dm_exec_sessions.client_interface_name,
	   sys.dm_exec_sql_text.text
FROM sys.dm_exec_connections
OUTER APPLY sys.dm_exec_sql_text(most_recent_sql_handle)
INNER JOIN sys.dm_exec_sessions ON sys.dm_exec_connections.session_id = sys.dm_exec_sessions.session_id
WHERE login_name = 'sa'
ORDER BY client_interface_name ASC

GO
EOF
cat /tmp/result.log

# session_id program_name                                                                                                                     client_interface_name            text                                                                                                                                                                                                                                                            
# ---------- -------------------------------------------------------------------------------------------------------------------------------- -------------------------------- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#         55 Microsoft JDBC Driver for SQL Server                                                                                             Microsoft JDBC Driver 7.2        SELECT MAX(start_lsn) FROM [testDB].cdc.lsn_time_mapping WHERE tran_id <> 0x00                                                                                                                                                                                  
#         61 Microsoft JDBC Driver for SQL Server                                                                                             Microsoft JDBC Driver 7.2        IF @@TRANCOUNT > 0 COMMIT TRAN                                                                                                                                                                                                                                  
#         56 SQLCMD                                                                                                                           ODBC                             USE testDB;

log "Printing all other information"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

SET NOCOUNT ON
SELECT sys.dm_exec_sessions.session_id,
       sys.dm_exec_sessions.program_name,
       sys.dm_exec_sessions.client_interface_name,
       sys.dm_exec_requests.*
FROM sys.dm_exec_requests
INNER JOIN sys.dm_exec_sessions ON sys.dm_exec_requests.session_id = sys.dm_exec_sessions.session_id
WHERE login_name = 'sa'
ORDER BY client_interface_name ASC

SELECT sys.dm_exec_sessions.session_id,
       sys.dm_exec_sessions.program_name,
       sys.dm_exec_sessions.client_interface_name,
       sys.dm_tran_active_transactions.*
FROM sys.dm_tran_active_transactions
INNER JOIN sys.dm_tran_session_transactions ON sys.dm_tran_active_transactions.transaction_id = sys.dm_tran_session_transactions.transaction_id
INNER JOIN sys.dm_exec_sessions ON sys.dm_tran_session_transactions.session_id = sys.dm_exec_sessions.session_id
WHERE login_name = 'sa'
ORDER BY client_interface_name ASC

SELECT sys.dm_tran_active_snapshot_database_transactions.*
FROM sys.dm_tran_active_snapshot_database_transactions
INNER JOIN sys.dm_tran_session_transactions ON sys.dm_tran_active_snapshot_database_transactions.transaction_id = sys.dm_tran_session_transactions.transaction_id
INNER JOIN sys.dm_exec_sessions ON sys.dm_tran_session_transactions.session_id = sys.dm_exec_sessions.session_id
WHERE login_name = 'sa'
ORDER BY client_interface_name ASC

SELECT *
FROM sys.dm_tran_persistent_version_store_stats
WHERE database_id = DB_ID('testDB')

GO
EOF
cat /tmp/result.log
