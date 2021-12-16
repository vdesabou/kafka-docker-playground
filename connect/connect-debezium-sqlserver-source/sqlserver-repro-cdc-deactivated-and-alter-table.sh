#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Load ./repro-cdc-deactivated/inventory.sql to SQL Server"
cat ./repro-cdc-deactivated/inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Verify that vincent has cdc access, it should not be empty"
cat ./repro-cdc-deactivated/verify-cdc-access.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U vincent -P Password!'

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

log "insert a record"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam2','Thomas','pam@office.com');
GO
EOF

sleep 5

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 5

log "Disable capture"
cat ./repro-cdc-deactivated/disable-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "alter table"
cat ./repro-ff-5391/alter-table.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

sleep 5

log "Enable capture"
cat ./repro-cdc-deactivated/enable-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Make an insert with phone_number"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email,phone_number) VALUES ('John','Doe','john.doe@example.com', '+1-555-123456');
GO
EOF

sleep 5

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginningit checkout -b 

# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com"}},"source":{"version":"1.7.1.Final","connector":"sqlserver","name":"server1","ts_ms":1639651251522,"snapshot":{"string":"true"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000410:0001"},"event_serial_no":null},"op":"r","ts_ms":{"long":1639651251525},"transaction":null}
# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1002,"first_name":"George","last_name":"Bailey","email":"gbailey@foobar.com"}},"source":{"version":"1.7.1.Final","connector":"sqlserver","name":"server1","ts_ms":1639651251529,"snapshot":{"string":"true"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000410:0001"},"event_serial_no":null},"op":"r","ts_ms":{"long":1639651251529},"transaction":null}
# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1003,"first_name":"Edward","last_name":"Walker","email":"ed@walker.com"}},"source":{"version":"1.7.1.Final","connector":"sqlserver","name":"server1","ts_ms":1639651251529,"snapshot":{"string":"true"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000410:0001"},"event_serial_no":null},"op":"r","ts_ms":{"long":1639651251529},"transaction":null}
# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1004,"first_name":"Anne","last_name":"Kretchmar","email":"annek@noanswer.org"}},"source":{"version":"1.7.1.Final","connector":"sqlserver","name":"server1","ts_ms":1639651251529,"snapshot":{"string":"last"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":null,"commit_lsn":{"string":"00000025:00000410:0001"},"event_serial_no":null},"op":"r","ts_ms":{"long":1639651251529},"transaction":null}
# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1005,"first_name":"Pam2","last_name":"Thomas","email":"pam@office.com"}},"source":{"version":"1.7.1.Final","connector":"sqlserver","name":"server1","ts_ms":1639651256073,"snapshot":{"string":"false"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":{"string":"00000025:000004e8:0003"},"commit_lsn":{"string":"00000025:000004e8:0005"},"event_serial_no":{"long":1}},"op":"c","ts_ms":{"long":1639651263078},"transaction":null}
# {"before":null,"after":{"server1.dbo.customers.Value":{"id":1006,"first_name":"John","last_name":"Doe","email":"john.doe@example.com","phone_number":{"string":"+1-555-123456"}}},"source":{"version":"1.7.1.Final","connector":"sqlserver","name":"server1","ts_ms":1639651274960,"snapshot":{"string":"false"},"db":"testDB","sequence":null,"schema":"dbo","table":"customers","change_lsn":{"string":"00000026:00000690:0003"},"commit_lsn":{"string":"00000026:00000690:0005"},"event_serial_no":{"long":1}},"op":"c","ts_ms":{"long":1639651276723},"transaction":null}
