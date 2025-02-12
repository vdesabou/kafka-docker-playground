#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ../../connect/connect-datagen-source/schemas/orders-template.avro > ../../connect/connect-datagen-source/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ../../connect/connect-datagen-source/schemas/shipments-template.avro > ../../connect/connect-datagen-source/schemas/shipments.avro

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


log "Create topic orders"
playground connector create-or-update --connector datagen-orders  << EOF
{
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
}
EOF

wait_for_datagen_connector_to_inject_data "orders" "10"

log "Create topic shipments"
playground connector create-or-update --connector datagen-shipments  << EOF
{
      "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
      "kafka.topic": "shipments",
      "key.converter": "org.apache.kafka.connect.storage.StringConverter",
      "value.converter": "org.apache.kafka.connect.json.JsonConverter",
      "value.converter.schemas.enable": "false",
      "max.interval": 1,
      "iterations": "10000",
      "tasks.max": "10",
      "schema.filename" : "/tmp/schemas/shipments.avro"
}
EOF

wait_for_datagen_connector_to_inject_data "shipments" "10"

log "Create topic products"

playground connector create-or-update --connector datagen-products  << EOF
{
      "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
      "kafka.topic": "products",
      "key.converter": "org.apache.kafka.connect.storage.StringConverter",
      "value.converter": "org.apache.kafka.connect.json.JsonConverter",
      "value.converter.schemas.enable": "false",
      "max.interval": 1,
      "iterations": "100",
      "tasks.max": "10",
      "schema.filename" : "/tmp/schemas/products.avro",
      "schema.keyfield" : "orderid"
}
EOF
wait_for_datagen_connector_to_inject_data "products" "10"

log "Create topic customers"
playground connector create-or-update --connector datagen-customers  << EOF
{
      "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
      "kafka.topic": "customers",
      "key.converter": "org.apache.kafka.connect.storage.StringConverter",
      "value.converter": "org.apache.kafka.connect.json.JsonConverter",
      "value.converter.schemas.enable": "false",
      "max.interval": 1,
      "iterations": "1000",
      "tasks.max": "10",
      "schema.filename" : "/tmp/schemas/customers.avro",
      "schema.keyfield" : "orderid"
}
EOF
wait_for_datagen_connector_to_inject_data "customers" "10"

sleep 10

log "Verify we have received the data in orders topic"
playground topic consume --topic orders --min-expected-messages 1 --timeout 60

log "Verify we have received the data in shipments topic"
playground topic consume --topic shipments --min-expected-messages 1 --timeout 60

log "Verify we have received the data in customers topic"
playground topic consume --topic customers --min-expected-messages 1 --timeout 60

log "Verify we have received the data in products topic"
playground topic consume --topic products --min-expected-messages 1 --timeout 60
