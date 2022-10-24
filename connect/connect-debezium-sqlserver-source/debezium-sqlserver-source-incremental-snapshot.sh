#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Create table"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
-- Create the test database
CREATE DATABASE testDB;
GO
USE testDB;
EXEC sys.sp_cdc_enable_db;

-- Create some customers ...
CREATE TABLE customers (
  id INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE
);
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Sally','Thomas','sally.thomas@acme.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('George','Bailey','gbailey@foobar.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Edward','Walker','ed@walker.com');
INSERT INTO customers(first_name,last_name,email)
  VALUES ('Anne','Kretchmar','annek@noanswer.org');
EXEC sys.sp_cdc_enable_table @source_schema = 'dbo', @source_name = 'customers', @role_name = NULL, @supports_net_changes = 0;
GO
EOF

# https://debezium.io/documentation/reference/1.9/configuration/signalling.html#sending-signals-to-a-debezium-connector
log "Creating a signaling data collection"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
CREATE TABLE debezium_signal (id VARCHAR(42) PRIMARY KEY, type VARCHAR(32) NOT NULL, data VARCHAR(2048) NULL);
EXEC sys.sp_cdc_enable_table @source_schema = 'dbo', @source_name = 'debezium_signal', @role_name = NULL, @supports_net_changes = 0;
GO
EOF

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
              "table.include.list" : "dbo.customers,dbo.debezium_signal",
              "signal.data.collection": "dbo.debezium_signal"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

log "Insert another row"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5


log "Add another table customers2"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
CREATE TABLE customers2 (
  id INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE
);
INSERT INTO customers2(first_name,last_name,email)
  VALUES ('Sally','Thomas','sally.thomas@acme.com');
INSERT INTO customers2(first_name,last_name,email)
  VALUES ('George','Bailey','gbailey@foobar.com');
INSERT INTO customers2(first_name,last_name,email)
  VALUES ('Edward','Walker','ed@walker.com');
INSERT INTO customers2(first_name,last_name,email)
  VALUES ('Anne','Kretchmar','annek@noanswer.org');
EXEC sys.sp_cdc_enable_table @source_schema = 'dbo', @source_name = 'customers2', @role_name = NULL, @supports_net_changes = 0;
GO
EOF


log "Updating Debezium SQL Server source connector with new table customers2"
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
              "table.include.list" : "dbo.customers,dbo.debezium_signal,dbo.customers2",
              "signal.data.collection": "dbo.debezium_signal"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

set +e
log "Verifying topic server1.dbo.customers2: it should be empty"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers2 --from-beginning --max-messages 4
set -e

log "Trigger Ad hoc snapshot"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO debezium_signal (id, type, data) VALUES('captain adhoc $RANDOM', 'execute-snapshot', '{"data-collections": ["dbo.customers2"], "type":"incremental"}');
GO
EOF


sleep 5

log "Verifying topic server1.dbo.customers2: it should have snapshot"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers2 --from-beginning --max-messages 4
