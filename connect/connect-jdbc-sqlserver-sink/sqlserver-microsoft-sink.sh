#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jdbc-sqlserver-sink
if [ ! -f ${PWD}/sqljdbc_12.2/enu/mssql-jdbc-12.2.0.jre11.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-12.2.0.jre11.jar"
     curl -L https://go.microsoft.com/fwlink/?linkid=2222954 -o sqljdbc_12.2.0.0_enu.tar.gz
     tar xvfz sqljdbc_12.2.1.0_enu.tar.gz
     rm -f sqljdbc_12.2.1.0_enu.tar.gz
fi
cd -

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.microsoft.yml"



log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:sqlserver://sqlserver:1433",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "topics": "orders",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5

log "Show content of orders table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
select * from orders
GO
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log