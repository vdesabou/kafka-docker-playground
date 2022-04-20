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
                    "tasks.max": "2",
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
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5



docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;

SET NOCOUNT ON

SELECT *
FROM sys.dm_exec_sessions
WHERE login_name = 'sa'
ORDER BY client_interface_name ASC

SELECT sys.dm_exec_sessions.session_id,
       sys.dm_exec_sessions.program_name,
	   sys.dm_exec_sessions.client_interface_name,
	   sys.dm_exec_sql_text.text
FROM sys.dm_exec_connections
OUTER APPLY sys.dm_exec_sql_text(most_recent_sql_handle)
INNER JOIN sys.dm_exec_sessions ON sys.dm_exec_connections.session_id = sys.dm_exec_sessions.session_id
WHERE login_name = 'sa'
ORDER BY client_interface_name ASC

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
