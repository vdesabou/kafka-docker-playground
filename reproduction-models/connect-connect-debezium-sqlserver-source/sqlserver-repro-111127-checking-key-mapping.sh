#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/sqljdbc_7.4/enu/mssql-jdbc-7.4.1.jre8.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-7.4.1.jre8.jar"
     wget https://download.microsoft.com/download/6/9/9/699205CA-F1F1-4DE9-9335-18546C5C8CBD/sqljdbc_7.4.1.0_enu.tar.gz
     tar xvfz sqljdbc_7.4.1.0_enu.tar.gz
     rm -f sqljdbc_7.4.1.0_enu.tar.gz
fi


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-111127-checking-key-mapping.yml"


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
               "transforms": "unwrap",
               "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
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

# {
#   "connect.name": "server1.dbo.customers.Value",
#   "fields": [
#     {
#       "name": "id",
#       "type": "int"
#     },
#     {
#       "name": "first_name",
#       "type": "string"
#     },
#     {
#       "name": "last_name",
#       "type": "string"
#     },
#     {
#       "name": "email",
#       "type": "string"
#     }
#   ],
#   "name": "Value",
#   "namespace": "server1.dbo.customers",
#   "type": "record"
# }

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "server1.dbo.customers",
               "auto.create": "true",
               "transforms": "addTopicSuffix",
               "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.addTopicSuffix.regex":"(.*)",
               "transforms.addTopicSuffix.replacement":"out"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .


sleep 5

log "Show content of out table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from out
GO
EOF
cat /tmp/result.log

# [2022-06-23 12:04:38,085] INFO [sqlserver-sink|task-0] Creating table with sql: CREATE TABLE "dbo"."out" (
# "id" int NOT NULL,
# "first_name" varchar(max) NOT NULL,
# "last_name" varchar(max) NOT NULL,
# "email" varchar(max) NOT NULL) (io.confluent.connect.jdbc.sink.DbStructure:122)