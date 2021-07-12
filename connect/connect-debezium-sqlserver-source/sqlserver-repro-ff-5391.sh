#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Load ./repro-ff-5391/inventory.sql to SQL Server"
cat ./repro-ff-5391/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Creating Debezium SQL Server source connector"
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

log "Connector status: it is running"
curl --request GET \
  --url http://localhost:8083/connectors/debezium-sqlserver-source/status \
  --header 'Accept: application/json' | jq .

log "Make an insert"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas','pam@office.com');
GO
EOF

sleep 5

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5


log "alter table (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-ff-5391/alter-table.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Create new capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-ff-5391/create-new-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

sleep 5

log "Make an insert with phone_number"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email,phone_number) VALUES ('John','Doe','john.doe@example.com', '+1-555-123456');
GO
EOF

sleep 5

log "Verifying topic server1.dbo.customers, we should see the message with the phone_number"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 6

# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1006,"first_name":"John","last_name":"Doe","email":"john.doe@example.com","phone_number":{"string":"+1-555-123456"}}},"source":{"version":"1.5.0.Final","connector":"sqlserver","name":"server1","ts_ms":1626081244747,"snapshot":{"string":"false"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":{"string":"00000025:00000d48:0003"},"commit_lsn":{"string":"00000025:00000d48:0005"},"event_serial_no":{"long":1}},"op":"c","ts_ms":{"long":1626081249542},"transaction":null}

log "Drop old capture (following https://debezium.io/documentation/reference/connectors/sqlserver.html#online-schema-updates)"
cat ./repro-ff-5391/drop-old-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'
