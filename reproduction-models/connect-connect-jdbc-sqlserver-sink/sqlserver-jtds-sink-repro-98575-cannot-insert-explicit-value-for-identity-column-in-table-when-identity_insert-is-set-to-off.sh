#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-98575-cannot-insert-explicit-value-for-identity-column-in-table-when-identity_insert-is-set-to-off.yml"

log "Load inventory-repro-98575.sql to SQL Server"
cat inventory-repro-98575.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'

log "Creating JDBC SQL Server (with JTDS driver) sink connector"
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
               "auto.evolve": "true",
               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "errors.retry.delay.max.ms": "60000",
               "errors.retry.timeout": "0"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "Sending messages to topic customers"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic customers --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"first_name", "type": "string"}]}' << EOF
{"first_name": "vincent"}
EOF

sleep 5

log "Show content of customers table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! > /tmp/result.log  2>&1 <<-EOF
use testDB;
select * from customers
GO
EOF
cat /tmp/result.log
grep "vincent" /tmp/result.log