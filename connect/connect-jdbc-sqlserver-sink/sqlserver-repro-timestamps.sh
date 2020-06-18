#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/sqljdbc_7.4/enu/mssql-jdbc-7.4.1.jre8.jar ]
then
     log "Downloading Microsoft JDBC driver mssql-jdbc-7.4.1.jre8.jar"
     wget https://download.microsoft.com/download/6/9/9/699205CA-F1F1-4DE9-9335-18546C5C8CBD/sqljdbc_7.4.1.0_enu.tar.gz
     tar xvfz sqljdbc_7.4.1.0_enu.tar.gz
     rm -f sqljdbc_7.4.1.0_enu.tar.gz
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-microsoft.yml"

# Removed pre-installed JTDS driver
docker exec connect rm -f /usr/share/confluent-hub-components/confluentinc-kafka-connect-jdbc/lib/jtds-1.3.1.jar
docker container restart connect

log "sleeping 60 seconds"
sleep 60

log "Creating JDBC SQL Server (with Microsoft driver) sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:sqlserver://sqlserver:1433",
                    "connection.user": "sa",
                    "connection.password": "Password!",
                    "topics": "orders",
                    "auto.create": "true",
                    "transforms": "timestampconversion",
                    "transforms.timestampconversion.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
                    "transforms.timestampconversion.target.type": "Timestamp",
                    "transforms.timestampconversion.format": "yyyy-MM-dd HH:mm:ss.SSS",
                    "transforms.timestampconversion.field": "tsm"
          }' \
     http://localhost:8083/connectors/sqlserver-sink/config | jq .

log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"fields":[{"type":"int","name":"id"},{"type":"string","name":"product"},{"type":"int","name":"quantity"},{"type":"float","name":"price"},{"type":"string","name":"tsm"}],"type":"record","name":"myrecord"}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50, "tsm": "2019-07-11 17:57:06.750"}
EOF


docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --from-beginning --max-messages 1

sleep 5

log "Show schema of orders table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
exec sp_help orders
GO
EOF

log "Show content of orders table:"
docker exec -i sqlserver /opt/mssql-tools/bin/sqlcmd -U sa -P Password! << EOF
select * from orders
GO
EOF