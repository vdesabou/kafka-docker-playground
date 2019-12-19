#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-jtds.yml"

echo -e "\033[0;33mCreating JDBC SQL Server (with JTDS driver) sink connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "topics": "orders",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

echo -e "\033[0;33mSending messages to topic orders\033[0m"
docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5

echo -e "\033[0;33mShow content of orders table:\033[0m"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
select * from orders
GO
EOF