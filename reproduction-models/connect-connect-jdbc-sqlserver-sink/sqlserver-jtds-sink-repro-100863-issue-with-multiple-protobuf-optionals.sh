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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-100863-issue-with-multiple-protobuf-optionals.yml"


log "Register schema for customers_protobuf-value"
curl -X POST -H "Content-Type: application/json" -d'
{
  "schemaType": "PROTOBUF",
  "schema": "syntax = \"proto3\";\n\npackage server1.dbo.customers;\n\n//doc entry\nmessage Value {\n//doc entry\nint32 field_no_optional = 1;\n//doc entry\noptional string field_first_optional = 2;\n//doc entry\noptional int32 field_second_optional = 3;\n//doc entry\noptional string field_third_optional = 4;\n}"
}' \
"http://localhost:8081/subjects/customers_protobuf-value/versions"

# syntax = "proto3";
# package server1.dbo.customers;

# message Value {
#   int32 field_no_optional = 1;
#   optional string field_first_optional = 2;
#   optional int32 field_second_optional = 3;
#   optional string field_third_optional = 4;
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
                "value.converter.optional.for.nullables":"true",

                "include.schema.changes": "false",

                "transforms": "Reroute,unwrap,extractKeyfromStruct",

                "transforms.Reroute.type": "org.apache.kafka.connect.transforms.RegexRouter",
                "transforms.Reroute.regex": "(.*)customers(.*)",
                "transforms.Reroute.replacement": "customers_protobuf",

                "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
                "transforms.unwrap.drop.tombstones": "false",

               "transforms.extractKeyfromStruct.type":"org.apache.kafka.connect.transforms.ValueToKey",
               "transforms.extractKeyfromStruct.fields":"field_no_optional"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers([field_first_optional],[field_second_optional],[field_third_optional]) VALUES ('Pam',1,'pam@office.com');
GO
EOF

log "Verifying topic customers_protobuf"
timeout 60 docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers_protobuf --from-beginning --max-messages 5

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB;selectMethod=cursor",
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
               "batch.size": "10",
               "auto.create": "true",
               "auto.evolve": "true",
               "quote.sql.identifiers": "always",

               "insert.mode":"insert",
               "transforms": "FlattenValue",
               "transforms.FlattenValue.type": "org.apache.kafka.connect.transforms.Flatten$Value",
               "transforms.Rename.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
               "transforms.Rename.renames": "_field_first_optional_0.field_first_optional:field_first_optional,_field_second_optional_1.field_second_optional:field_second_optional,_field_third_optional_2.field_third_optional:field_third_optional"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .


# [2022-04-19 09:38:38,048] INFO [sqlserver-sink|task-0] Creating table with sql: CREATE TABLE "dbo"."customers_protobuf" (
# "field_no_optional" int NULL,
# "field_first_optional" varchar(max) NULL,
# "field_second_optional" int NULL,
# "field_third_optional" varchar(max) NULL) (io.confluent.connect.jdbc.sink.DbStructure:122)


sleep 5

log "Show content of customers_protobuf table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
USE testDB;
select * from customers_protobuf
GO
EOF
cat /tmp/result.log

# 09:38:39 ℹ️ Show content of customers_protobuf table:
# field_no_optional field_first_optional                                                                                                                                                                                                                                             field_second_optional field_third_optional                                                                                                                                                                                                                                            
# ----------------- ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- --------------------- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#              1001 Sally                                                                                                                                                                                                                                                                                1 sally.thomas@acme.com                                                                                                                                                                                                                                           
#              1002 George                                                                                                                                                                                                                                                                               1 gbailey@foobar.com                                                                                                                                                                                                                                              
#              1003 Edward                                                                                                                                                                                                                                                                               1 ed@walker.com                                                                                                                                                                                                                                                   
#              1004 Anne                                                                                                                                                                                                                                                                                 1 annek@noanswer.org                                                                                                                                                                                                                                              
#              1001 Sally                                                                                                                                                                                                                                                                                1 sally.thomas@acme.com                                                                                                                                                                                                                                           
#              1002 George                                                                                                                                                                                                                                                                               1 gbailey@foobar.com                                                                                                                                                                                                                                              
#              1003 Edward                                                                                                                                                                                                                                                                               1 ed@walker.com                                                                                                                                                                                                                                                   
#              1004 Anne                                                                                                                                                                                                                                                                                 1 annek@noanswer.org                                                                                                                                                                                                                                              
#              1001 Sally                                                                                                                                                                                                                                                                                1 sally.thomas@acme.com                                                                                                                                                                                                                                           
#              1002 George                                                                                                                                                                                                                                                                               1 gbailey@foobar.com                                                                                                                                                                                                                                              
#              1003 Edward                                                                                                                                                                                                                                                                               1 ed@walker.com                                                                                                                                                                                                                                                   
#              1004 Anne                                                                                                                                                                                                                                                                                 1 annek@noanswer.org                                                                                                                                                                                                                                              
#              1005 Pam                                                                                                                                                                                                                                                                                  1 pam@office.com                                                                                                                                                                                                                                                  
#              1001 Sally                                                                                                                                                                                                                                                                                1 sally.thomas@acme.com                                                                                                                                                                                                                                           
#              1002 George                                                                                                                                                                                                                                                                               1 gbailey@foobar.com                                                                                                                                                                                                                                              
#              1003 Edward                                                                                                                                                                                                                                                                               1 ed@walker.com                                                                                                                                                                                                                                                   
#              1004 Anne                                                                                                                                                                                                                                                                                 1 annek@noanswer.org                                                                                                                                                                                                                                              
#              1005 Pam                                                                                                                                                                                                                                                                                  1 pam@office.com                                                                                                                                                                                                                                                  

# (18 rows affected)