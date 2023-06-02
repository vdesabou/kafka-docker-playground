#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Create JDBC Sybase sink connector"
playground connector create-or-update --connector sybase-sink << EOF
{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:jtds:sybase://sybase:5000",
               "connection.user": "sa",
               "connection.password": "password",
               "topics": "orders",
               "auto.create": "true"
          }
EOF

log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price","type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5

log "Show content of orders table:"
docker exec -i sybase /sybase/isql -S -Usa -Ppassword > /tmp/result.log  2>&1 <<-EOF
select * from orders
GO
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log
