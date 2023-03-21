#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ../../connect/connect-datagen-source/schemas/orders-template.avro > ../../connect/connect-datagen-source/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ../../connect/connect-datagen-source/schemas/shipments-template.avro > ../../connect/connect-datagen-source/schemas/shipments.avro

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Create topic orders"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "orders",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "10000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/orders.avro",
                "schema.keyfield" : "orderid"
            }' \
      http://localhost:8083/connectors/datagen-orders/config | jq .

wait_for_datagen_connector_to_inject_data "orders" "10"

log "Create topic shipments"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "shipments",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "10000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/shipments.avro"
            }' \
      http://localhost:8083/connectors/datagen-shipments/config | jq .

wait_for_datagen_connector_to_inject_data "shipments" "10"

log "Create topic products"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "products",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "100",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/products.avro",
                "schema.keyfield" : "productid"
            }' \
      http://localhost:8083/connectors/datagen-products/config | jq .

wait_for_datagen_connector_to_inject_data "products" "10"

log "Create topic customers"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "customers",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "1000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/customers.avro",
                "schema.keyfield" : "customerid"
            }' \
      http://localhost:8083/connectors/datagen-customers/config | jq .

wait_for_datagen_connector_to_inject_data "customers" "10"

sleep 10

log "Verify we have received the data in orders topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic orders --from-beginning --max-messages 1

log "Verify we have received the data in shipments topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic shipments --from-beginning --max-messages 1

log "Verify we have received the data in customers topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic customers --from-beginning --max-messages 1

log "Verify we have received the data in products topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic products --from-beginning --max-messages 1
