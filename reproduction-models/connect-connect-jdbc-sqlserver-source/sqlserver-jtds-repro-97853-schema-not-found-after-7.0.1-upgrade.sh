#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-97853-schema-not-found-after-7.0.1-upgrade.yml"


log "Load inventory-repro-97853-schema-not-found-after-7.0.1-upgrade.sqlto SQL Server"
cat inventory-repro-97853-schema-not-found-after-7.0.1-upgrade.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


log "Register schema for sqlserver-customers-value"
curl -X POST http://localhost:8081/subjects/sqlserver-customers-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "syntax = \"proto3\"; message customers {int32 id = 1;string first_name = 2;string last_name = 3;string email = 4;}",
    "schemaType": "PROTOBUF"
}'

log "Creating JDBC SQL Server (with JTDS driver) source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
                    "errors.log.include.messages": "true",

                    "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.connect.meta.data": "false",

                    "value.converter.auto.register.schemas": "false",
                    "value.converter.use.latest.version": "true",
                    "value.converter.latest.compatibility.strict": "false"
          }' \
     http://localhost:8083/connectors/sqlserver-source/config | jq .




sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email) VALUES ('Pam','Thomas','pam@office.com');
GO
EOF

log "Verifying topic sqlserver-customers"
timeout 60 docker exec connect kafka-protobuf-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sqlserver-customers --from-beginning --max-messages 5
