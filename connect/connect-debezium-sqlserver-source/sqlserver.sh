#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Load inventory.sql to SQL Server"
cat inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


echo "Creating Debezium SQL Server source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "debezium-sqlserver-source",
               "config": {
                    "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
                    "tasks.max": "1",
                    "database.hostname": "sqlserver",
                    "database.port": "1433",
                    "database.user": "sa",
                    "database.password": "Password!",
                    "database.server.name": "server1",
                    "database.dbname" : "testDB",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.inventory"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

echo "Verifying topic server1.dbo.customers"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic server1.dbo.customers --from-beginning --max-messages 5
