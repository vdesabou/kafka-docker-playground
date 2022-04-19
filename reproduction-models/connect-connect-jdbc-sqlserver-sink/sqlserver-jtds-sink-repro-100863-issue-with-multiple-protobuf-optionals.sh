#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

log "Creating JDBC SQL Server (with JTDS driver) source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                "tasks.max": "1",
                "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB",
                "connection.user": "sa",
                "connection.password": "Password!",
                "mode": "bulk",

                "query": "select * from customers",
                "poll.interval.ms": "5000",
                "batch.max.rows": "1000",

                "topic.prefix": "customers_protobuf",
                "errors.retry.timeout": "3600000",
                "errors.retry.delay.max.ms": "60000",
                "errors.log.enable": "true",
                "errors.log.include.messages": "true",


                "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
                "value.converter.schema.registry.url": "http://schema-registry:8081",
                "value.converter.auto.register.schemas": "false",
                "value.converter.connect.meta.data": "false",
                "value.converter.use.latest.version": "true",
                "value.converter.latest.compatibility.strict": "false"
          }' \
     http://localhost:8083/connectors/sqlserver-source/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers([field_first_optional],[field_second_optional],[field_third_optional]) VALUES ('Pam',1,'pam@office.com');
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


# [2022-04-19 09:38:38,048] INFO [sqlserver-sink|task-0] Creating table with sql: CREATE TABLE "dbo"."customers_protobuf" (
# "field_no_optional" int NULL,
# "field_first_optional" varchar(max) NULL,
# "field_second_optional" int NULL,
# "field_third_optional" varchar(max) NULL) (io.confluent.connect.jdbc.sink.DbStructure:122)


sleep 5

log "Show content of customers_protobuf table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
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