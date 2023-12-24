#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


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
  email VARCHAR(255) NOT NULL
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
playground connector create-or-update --connector debezium-sqlserver-source  << EOF
{
  "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
  "tasks.max": "1",
  "database.hostname": "sqlserver",
  "database.port": "1433",
  "database.user": "sa",
  "database.password": "Password!",
  "database.names" : "testDB",

  "table.include.list" : "dbo.customers,dbo.debezium_signal",
  "signal.data.collection": "dbo.debezium_signal",

  "_comment": "old version before 2.x",
  "database.server.name": "server1",
  "database.history.kafka.bootstrap.servers": "broker:9092",
  "database.history.kafka.topic": "schema-changes.inventory",
  "_comment": "new version since 2.x",
  "database.encrypt": "false",
  "topic.prefix": "server1",
  "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
  "schema.history.internal.kafka.topic": "schema-changes.inventory"
}
EOF

sleep 5

log "Insert another row"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic server1.testDB.dbo.customers"
playground topic consume --topic server1.testDB.dbo.customers --min-expected-messages 5 --timeout 60


log "Add another table customers2"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
CREATE TABLE customers2 (
  id INTEGER IDENTITY(1001,1) NOT NULL PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL
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
playground connector create-or-update --connector debezium-sqlserver-source  << EOF
{
  "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
  "tasks.max": "1",
  "database.hostname": "sqlserver",
  "database.port": "1433",
  "database.user": "sa",
  "database.password": "Password!",
  "database.names" : "testDB",

  "table.include.list" : "dbo.customers,dbo.debezium_signal,dbo.customers2",
  "signal.data.collection": "testDB.dbo.debezium_signal",

  "_comment": "old version before 2.x",
  "database.server.name": "server1",
  "database.history.kafka.bootstrap.servers": "broker:9092",
  "database.history.kafka.topic": "schema-changes.inventory",
  "_comment": "new version since 2.x",
  "database.encrypt": "false",
  "topic.prefix": "server1",
  "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
  "schema.history.internal.kafka.topic": "schema-changes.inventory",

  "_comment:": "remove _ to use ExtractNewRecordState smt",
  "_transforms": "unwrap",
  "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF

log "Add another table customers2"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers2(first_name,last_name,email)
  VALUES ('Anne2','Kretchmar2','annek2@noanswer.org');
GO
EOF

sleep 30

log "Verifying topic server1.testDB.dbo.customers2 : there will be only the new record"
playground topic consume --topic server1.testDB.dbo.customers2 --min-expected-messages 1 --timeout 60

log "Trigger Ad hoc snapshot"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO debezium_signal (id, type, data) VALUES('captain adhoc $RANDOM', 'execute-snapshot', '{"data-collections": ["testDB.dbo.customers2"], "type":"incremental"}');
GO
EOF


sleep 5

log "Verifying topic server1.testDB.dbo.customers2: it should have all records"
playground topic consume --topic server1.testDB.dbo.customers2 --min-expected-messages 5 --timeout 60
