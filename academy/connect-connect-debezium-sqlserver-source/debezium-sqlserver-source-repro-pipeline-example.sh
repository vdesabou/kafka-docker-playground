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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-pipeline-example.yml"


log "Create table"
docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd -C -No -U sa -P Password! << EOF
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
  
  "_comment": "old version before 2.x",
  "database.server.name": "server1",
  "database.history.kafka.bootstrap.servers": "broker:9092",
  "database.history.kafka.topic": "schema-changes.inventory",
  "_comment": "new version since 2.x",
  "database.encrypt": "false",
  "topic.prefix": "server1",
  "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
  "schema.history.internal.kafka.topic": "schema-changes.inventory",

  "transforms": "unwrap,RemoveDots",
  "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.RemoveDots.regex": "(.*)\\\\.(.*)\\\\.(.*)",
  "transforms.RemoveDots.replacement": "mytable",
  "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF

sleep 5

docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd -C -No -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic mytable"
playground topic consume --topic mytable --min-expected-messages 5 --timeout 60
# {"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com"}
# {"id":1002,"first_name":"George","last_name":"Bailey","email":"gbailey@foobar.com"}
# {"id":1003,"first_name":"Edward","last_name":"Walker","email":"ed@walker.com"}
# {"id":1004,"first_name":"Anne","last_name":"Kretchmar","email":"annek@noanswer.org"}
# {"id":1005,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com"}

log "Creating JDBC PostgreSQL sink connector"
playground connector create-or-update --connector postgres-sink  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "mytable",
  "auto.create": "true",
  "transforms": "flatten",
  "transforms.flatten.type": "org.apache.kafka.connect.transforms.Flatten\$Value",
  "transforms.flatten.delimiter": "."
}
EOF



sleep 5

log "Show content of mytable table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM mytable'" > /tmp/result.log  2>&1
cat /tmp/result.log
#   id  | first_name | last_name |         email         
# ------+------------+-----------+-----------------------
#  1001 | Sally      | Thomas    | sally.thomas@acme.com
#  1002 | George     | Bailey    | gbailey@foobar.com
#  1003 | Edward     | Walker    | ed@walker.com
#  1004 | Anne       | Kretchmar | annek@noanswer.org
#  1005 | Pam        | Thomas    | pam@office.com
# (5 rows)
