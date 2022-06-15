#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-109831-replacefield-smt-not-working-as-expected.yml"

log "Creating JDBC PostgreSQL sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
               "topics": "orders",
               "auto.create": "true",
               "fields.whitelist": "id,product,quantity,price",
               "transforms": "Transform",
               "transforms.Transform.renames": "product:product2",
               "transforms.Transform.type": "org.apache.kafka.connect.transforms.ReplaceField$Value"
          }' \
     http://localhost:8083/connectors/postgres-sink/config | jq .


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5

# [2022-06-15 12:32:24,997] INFO [postgres-sink|task-0] Setting metadata for table "orders" to Table{name='"orders"', type=TABLE columns=[Column{'id', isPrimaryKey=false, allowsNull=false, sqlType=int4}, Column{'price', isPrimaryKey=false, allowsNull=false, sqlType=float4}, Column{'quantity', isPrimaryKey=false, allowsNull=false, sqlType=int4}]} (io.confluent.connect.jdbc.util.TableDefinitions:64)

log "Show content of ORDERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM ORDERS'" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "foo" /tmp/result.log | grep "100"

#  id  | quantity | price 
# -----+----------+-------
#  999 |      100 |    50
# (1 row)