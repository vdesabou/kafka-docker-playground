#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Load ./repro-no-cdc-role/inventory.sql to SQL Server"
cat ./repro-no-cdc-role/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Verify that vincent has no cdc permission, it should be empty"
cat ./repro-no-cdc-role/verify-cdc-access.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U vincent -P Password!'

log "Creating Debezium SQL Server source connector, using vincent"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
              "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
              "tasks.max": "1",
              "database.hostname": "sqlserver",
              "database.port": "1433",
              "database.user": "vincent",
              "database.password": "Password!",
              "database.server.name": "server1",
              "database.dbname" : "testDB",
              "database.history.kafka.bootstrap.servers": "broker:9092",
              "database.history.kafka.topic": "schema-changes.inventory"
          }' \
     http://localhost:8083/connectors/debezium-sqlserver-source/config | jq .

sleep 5

log "Connector status"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .


docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas','pam@office.com');
GO
EOF

sleep 5

log "Connector status"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .

log "Verifying topic server1.dbo.customers: it only show snapshot records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5
