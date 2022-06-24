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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.microsoft.repro-110836-binary-handling-with-null-value.yml"

log "Load inventory-repro-110836.sql to SQL Server"
cat inventory-repro-110836.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433;databaseName=testDB",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "customers",
               "auto.create": "false",
               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",

               "binary.handling.mode": "bytes",
               "delete.enabled" : "true",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name":"dlq",
               "errors.deadletterqueue.topic.replication.factor": 1,
               "errors.deadletterqueue.context.headers.enable":true,
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "errors.retry.delay.max.ms": "6000",
               "errors.retry.timeout": "0",
               "errors.tolerance": "all",
               "insert.mode": "upsert",
               "time.precision.mode": "connect",
               "transforms.ReplaceField.blacklist": "", 
               "transforms.ReplaceField.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
               "transforms": "ReplaceField",
               "pk.mode": "record_key",
               "pk.fields": "f0"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .


log "send messages to customers"
docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property key.schema='{"type":"object","properties":{"f0":{"type":"string"}}}' --property value.schema='{"type":"object","properties":{"f1":{"type":"string"},"f2":{"oneOf": [ {"type": "null"},{"connect.type": "bytes","type": "string"}]}}}'  --property parse.key=true --property key.separator="|" << EOF
{"f0": "1"}|{"f1": "1","f2":"ZG1Gc2RXVXg="}
{"f0": "2"}|{"f1": "2","f2":null}
EOF

#  Creating table with sql: CREATE TABLE "dbo"."customers" (
# "f1" varchar(max) NOT NULL,
# "f2" varbinary(max) NULL)

sleep 5

log "Show content of customers table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
use testDB
select * from customers
GO
EOF
cat /tmp/result.log
