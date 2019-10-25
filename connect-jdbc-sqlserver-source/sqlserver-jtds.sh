#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext-jtds.yml"


echo "Load inventory.sql to SQL Server"
cat inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


echo "Creating JDBC SQL Server (with JTDS driver) source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "sqlserver-source",
               "config": {
                    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:jtds:sqlserver://sqlserver:1433/testDB",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "table.whitelist": "customers",
                    "mode": "incrementing",
                    "incrementing.column.name": "id",
                    "topic.prefix": "sqlserver-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

echo "Verifying topic sqlserver-customers"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic sqlserver-customers --from-beginning --max-messages 5
