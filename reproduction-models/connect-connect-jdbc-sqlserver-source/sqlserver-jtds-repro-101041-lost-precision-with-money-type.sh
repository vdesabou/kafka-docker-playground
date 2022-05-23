#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.jtds.repro-101041-lost-precision-with-money-type.yml"


log "Load inventory.sql to SQL Server"
cat repro-101041-inventory.sql | docker exec -i sqlserver bash -c '/opt/mssql-tools/bin/sqlcmd -U sa -P Password!'


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
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/sqlserver-source/config | jq .

sleep 5

docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
USE testDB;
INSERT INTO customers(first_name,last_name,email,original_value) VALUES ('Pam','Thomas','pam@office.com',10000.0001);
GO
EOF

log "Verifying topic sqlserver-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sqlserver-customers --from-beginning --max-messages 2

# without cast
# {"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com","original_value":{"bytes":"\u0005õá\u0000"}}
# {"id":1002,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com","original_value":{"bytes":"\u0005õá\u0000"}}


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
               "topic.prefix": "sqlservercast-",
               "validate.non.null":"false",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "transforms": "Cast",
               "transforms.Cast.type": "org.apache.kafka.connect.transforms.Cast$Value",
               "transforms.Cast.spec": "original_value:float64"
          }' \
     http://localhost:8083/connectors/sqlservercast-source/config | jq .

log "Verifying topic sqlservercast-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic sqlservercast-customers --from-beginning --max-messages 2

# {"id":1001,"first_name":"Sally","last_name":"Thomas","email":"sally.thomas@acme.com","original_value":{"double":10000.0}}
# {"id":1002,"first_name":"Pam","last_name":"Thomas","email":"pam@office.com","original_value":{"double":10000.0001}}