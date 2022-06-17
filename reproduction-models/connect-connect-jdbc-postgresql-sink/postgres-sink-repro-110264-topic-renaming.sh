#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-110264-topic-renaming.yml"

log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
               "topics": "blah.blah.orders,blah.blah.orderspre",
               "table.name.format": "${topic}",
               "auto.create": "true",
               "transforms": "dropPrefix",
               "transforms.dropPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.dropPrefix.regex": "blah.blah.(.*)",
               "transforms.dropPrefix.replacement": "$1"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .


log "Sending messages to topic blah.blah.orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic blah.blah.orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

log "Sending messages to topic  blah.blah.orderspre"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic blah.blah.orderspre --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5

log "Show content of ORDERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM ORDERS'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log | grep "100"

log "Show content of ORDERSPRE table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM ORDERSPRE'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log | grep "100"