#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-100863-issue-with-multiple-protobuf-optionals.yml"


log "Register schema for customers_protobuf-value"
curl -X POST -H "Content-Type: application/json" -d'
{
  "schemaType": "PROTOBUF",
  "schema": "syntax = \"proto3\";\n\npackage server1.dbo.customers;\n\nmessage Value {\nint32 id = 1;\noptional string first_name = 2;\noptional string last_name = 3;\noptional string email = 4;\n}"
}' \
"http://localhost:8081/subjects/customers_protobuf-value/versions"

# syntax = "proto3";
# package server1.dbo.customers;

# message Value {
#   int32 id = 1;
#   optional string first_name = 2;
#   optional string last_name = 3;
#   optional string email = 4;
# }

log "Load inventory-repro-100863.sql to SQL Server"
cat inventory-repro-100863.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

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

                "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
                "value.converter.schema.registry.url": "http://schema-registry:8081",
                "value.converter.auto.register.schemas": "false",
                "value.converter.connect.meta.data": "false",
                "value.converter.use.latest.version": "true",
                "value.converter.latest.compatibility.strict": "false",

                "include.schema.changes": "false",

                "transforms": "Reroute,unwrap",

                "transforms.Reroute.type": "org.apache.kafka.connect.transforms.RegexRouter",
                "transforms.Reroute.regex": "(.*)customers(.*)",
                "transforms.Reroute.replacement": "customers_protobuf",

                "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
                "transforms.unwrap.drop.tombstones": "false"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic customers_protobuf"
timeout 60 docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers_protobuf --from-beginning --max-messages 5

log "Creating JDBC SQL Server (with JTDS driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                "tasks.max": "1",
                "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433",
                "connection.user": "sa",
                "connection.password": "Password!",
                "topics": "customers_protobuf",
                "auto.create": "true",
                "auto.evolve": "true",
                "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
                "value.converter.schema.registry.url": "http://schema-registry:8081",
                "value.converter.auto.register.schemas" : "false", 
                "value.converter.schemas.enable" : "false", 
                "value.converter.connect.meta.data" : "false", 
                "value.converter.use.latest.version" : "true", 
                "value.converter.latest.compatibility.strict" : "false",
                "quote.sql.identifiers": "always"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .


# [2022-04-19 08:02:29,196] INFO [sqlserver-sink|task-0] Creating table with sql: CREATE TABLE "dbo"."customers_protobuf" (
# "id" int NULL,
# "first_name" varchar(max) NULL,
# "last_name" varchar(max) NULL,
# "email" varchar(max) NULL) (io.confluent.connect.jdbc.sink.DbStructure:122)


sleep 5

log "Show content of customers_protobuf table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from customers_protobuf
GO
EOF
cat /tmp/result.log


# 08:02:30 ℹ️ Show content of customers_protobuf table:
# id          first_name                                                                                                                                                                                                                                                       last_name                                                                                                                                                                                                                                                        email                                                                                                                                                                                                                                                           
# ----------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#        1001 Sally                                                                                                                                                                                                                                                            Thomas                                                                                                                                                                                                                                                           sally.thomas@acme.com                                                                                                                                                                                                                                           
#        1002 George                                                                                                                                                                                                                                                           Bailey                                                                                                                                                                                                                                                           gbailey@foobar.com                                                                                                                                                                                                                                              
#        1003 Edward                                                                                                                                                                                                                                                           Walker                                                                                                                                                                                                                                                           ed@walker.com                                                                                                                                                                                                                                                   
#        1004 Anne                                                                                                                                                                                                                                                             Kretchmar                                                                                                                                                                                                                                                        annek@noanswer.org                                                                                                                                                                                                                                              
#        1005 Pam                                                                                                                                                                                                                                                              Thomas                                                                                                                                                                                                                                                           pam@office.com                                                                                                                                                                                                                                                  

# (5 rows affected)
#        1002 George                                                                                                                                                                                                                                                           Bailey                                                                                                                                                                                                                                                           gbailey@foobar.com                                                                                                                                        