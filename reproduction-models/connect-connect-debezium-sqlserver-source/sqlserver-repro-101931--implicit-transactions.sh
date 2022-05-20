#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-101931--implicit-transactions.yml"


log "Load inventory.sql to SQL Server"
cat ../../connect/connect-debezium-sqlserver-source/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


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
                    "database.history.kafka.topic": "schema-changes.inventory",
                    "max.iteration.transactions": 1
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam4@office.com');
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

log "Printing connections for Debezium (program_name=Microsoft JDBC Driver for SQL Server)"
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


log "Printing transactions for Debezium (program_name=Microsoft JDBC Driver for SQL Server)"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

SET NOCOUNT ON

SELECT sys.dm_exec_sessions.session_id,
       sys.dm_exec_sessions.program_name,
       sys.dm_exec_sessions.client_interface_name,
       sys.dm_tran_active_transactions.*
FROM sys.dm_tran_active_transactions
INNER JOIN sys.dm_tran_session_transactions ON sys.dm_tran_active_transactions.transaction_id = sys.dm_tran_session_transactions.transaction_id
INNER JOIN sys.dm_exec_sessions ON sys.dm_tran_session_transactions.session_id = sys.dm_exec_sessions.session_id
WHERE login_name = 'sa'
ORDER BY client_interface_name ASC
GO
EOF
cat /tmp/result.log



docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

SET NOCOUNT ON

select transaction_id, name, transaction_begin_time
 ,case transaction_type 
    when 1 then '1 = Read/write transaction'
    when 2 then '2 = Read-only transaction'
    when 3 then '3 = System transaction'
    when 4 then '4 = Distributed transaction'
end as transaction_type 
,case transaction_state 
    when 0 then '0 = The transaction has not been completely initialized yet'
    when 1 then '1 = The transaction has been initialized but has not started'
    when 2 then '2 = The transaction is active'
    when 3 then '3 = The transaction has ended. This is used for read-only transactions'
    when 4 then '4 = The commit process has been initiated on the distributed transaction'
    when 5 then '5 = The transaction is in a prepared state and waiting resolution'
    when 6 then '6 = The transaction has been committed'
    when 7 then '7 = The transaction is being rolled back'
    when 8 then '8 = The transaction has been rolled back'
end as transaction_state
,case dtc_state 
    when 1 then '1 = ACTIVE'
    when 2 then '2 = PREPARED'
    when 3 then '3 = COMMITTED'
    when 4 then '4 = ABORTED'
    when 5 then '5 = RECOVERED'
end as dtc_state 
,transaction_status, transaction_status2,dtc_status, dtc_isolation_level, filestream_transaction_id
from sys.dm_tran_active_transactions 

GO
EOF
cat /tmp/result.log


docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

SET NOCOUNT ON

SELECT
trans.session_id AS [SESSION ID],
ESes.host_name AS [HOST NAME],login_name AS [Login NAME],
trans.transaction_id AS [TRANSACTION ID],
tas.name AS [TRANSACTION NAME],tas.transaction_begin_time AS [TRANSACTION 
BEGIN TIME],
tds.database_id AS [DATABASE ID],DBs.name AS [DATABASE NAME]
FROM sys.dm_tran_active_transactions tas
JOIN sys.dm_tran_session_transactions trans
ON (trans.transaction_id=tas.transaction_id)
LEFT OUTER JOIN sys.dm_tran_database_transactions tds
ON (tas.transaction_id = tds.transaction_id )
LEFT OUTER JOIN sys.databases AS DBs
ON tds.database_id = DBs.database_id
LEFT OUTER JOIN sys.dm_exec_sessions AS ESes
ON trans.session_id = ESes.session_id
WHERE ESes.session_id IS NOT NULL 

GO
EOF
cat /tmp/result.log

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

exit 0

curl -X POST localhost:8083/connectors/debezium-sqlserver-source/tasks/0/restart


docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

KILL 55

GO
EOF
cat /tmp/result.log