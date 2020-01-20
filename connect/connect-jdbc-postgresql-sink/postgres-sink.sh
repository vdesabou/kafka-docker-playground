#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating JDBC PostgreSQL sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=postgres&password=postgres&ssl=false",
                    "topics": "orders",
                    "auto.create": "true"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq_docker_cli .


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5


log "Show content of ORDERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM ORDERS'"