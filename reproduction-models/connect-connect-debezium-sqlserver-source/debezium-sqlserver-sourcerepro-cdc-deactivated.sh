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

#log "display connector offset"
#timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1
docker logs connect 2>&1 | egrep "Lsn|lsn"

log "Display Min and Max LSN"
cat ./repro-cdc-deactivated/lsn.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Disable capture"
cat ./repro-cdc-deactivated/disable-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "insert a record"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Capture disabled','Capture disabled','capture_disabled@office.com');
GO
EOF

sleep 5

#log "display connector offset"
#timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1
docker logs connect 2>&1 | egrep "Lsn|lsn"

log "Display Min and Max LSN"
cat ./repro-cdc-deactivated/lsn.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Enable capture"
cat ./repro-cdc-deactivated/enable-capture.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

#log "display connector offset"
#timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1
docker logs connect 2>&1 | egrep "Lsn|lsn"

log "Display Min and Max LSN"
cat ./repro-cdc-deactivated/lsn.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "insert a record"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Capture enabled','Capture enabled','capture_enabled@office.com');
GO
EOF

sleep 5

#log "display connector offset"
#timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1
docker logs connect 2>&1 | egrep "Lsn|lsn"

log "Display Min and Max LSN"
cat ./repro-cdc-deactivated/lsn.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Verifying topic server1.dbo.customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1.dbo.customers --from-beginning --max-messages 7