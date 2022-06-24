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

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:sqlserver://sqlserver:1433",
               "connection.user": "sa",
               "connection.password": "Password!",
               "topics": "customer_json_schema",
               "auto.create": "true",
               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .


log "send messages to customer_json_schema"
docker exec -i connect kafka-json-schema-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customer_json_schema --property value.schema='{"type":"object","properties":{"f1":{"type":"string"},"f2":{"oneOf": [ {"type": "null"},{"connect.type": "bytes","type": "string"}]}}}' << EOF
{"f1": "1","f2":"ZG1Gc2RXVXg="}
{"f1": "2","f2":"ZG1Gc2RXVXg="}
{"f1": "3","f2":"ZG1Gc2RXVXg="}
EOF


sleep 5

log "Show content of customer_json_schema table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from customer_json_schema
GO
EOF
cat /tmp/result.log
