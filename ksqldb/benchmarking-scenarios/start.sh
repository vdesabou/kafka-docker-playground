#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


function throughtput () {
  stream="$1"
  duration="$2"

  totalmessages=$(playground ksqldb describe --source "$stream" --json | jq '.stats."total-messages" // 0 | floor')
  throughput=$(echo $((totalmessages / duration)))
  log "🚀 Stream $stream has processed $totalmessages messages. Took $duration seconds. Throughput=$throughput msg/s"
}

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/orders-template.avro > ${DIR}/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/shipments-template.avro > ${DIR}/schemas/shipments.avro

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create topic orders"
playground connector create-or-update --connector datagen-orders --no-wait << EOF
{
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
    "kafka.topic": "orders",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "max.interval": 1,
    "iterations": "10000",
    "tasks.max": "10",
    "schema.filename": "/tmp/schemas/orders.avro",
    "schema.keyfield": "orderid"
}
EOF

wait_for_datagen_connector_to_inject_data "orders" "10"

log "Create topic shipments"
playground connector create-or-update --connector datagen-shipments --no-wait << EOF
{
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
    "kafka.topic": "shipments",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "max.interval": 1,
    "iterations": "10000",
    "tasks.max": "10",
    "schema.filename": "/tmp/schemas/shipments.avro"
}
EOF

wait_for_datagen_connector_to_inject_data "shipments" "10"

log "Create topic products"
playground connector create-or-update --connector datagen-products --no-wait << EOF
{
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
    "kafka.topic": "products",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "max.interval": 1,
    "iterations": "100",
    "tasks.max": "10",
    "schema.filename": "/tmp/schemas/products.avro",
    "schema.keyfield": "productid"
}
EOF

wait_for_datagen_connector_to_inject_data "products" "10"

log "Create topic customers"
playground connector create-or-update --connector datagen-customers --no-wait << EOF
{
    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
    "kafka.topic": "customers",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "max.interval": 1,
    "iterations": "1000",
    "tasks.max": "10",
    "schema.filename": "/tmp/schemas/customers.avro",
    "schema.keyfield": "customerid"
}
EOF

wait_for_datagen_connector_to_inject_data "customers" "10"

log "Create the ksqlDB tables and streams"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE TABLE CUSTOMERS
(
    customerid varchar PRIMARY KEY,
    firstname varchar,
    lastname varchar, gender varchar,
    random_data varchar,
    address struct<street varchar, city varchar, state varchar, zipcode bigint>
)
WITH
    (kafka_topic='customers', value_format='json');

CREATE TABLE PRODUCTS
(
    productid varchar PRIMARY KEY,
    name varchar,
    category varchar,
    description varchar
)
WITH
    (kafka_topic='products', value_format='json');

CREATE STREAM ORDERS
(
    ordertime bigint,
    orderid bigint,
    productid varchar,
    orderunits integer,
    order_category varchar,
    customerid varchar
)
WITH
    (kafka_topic= 'orders', value_format='json', timestamp='ordertime');

CREATE STREAM SHIPMENTS
(
    SHIPMENT_TIME bigint,
    SHIPMENTID bigint,
    orderid bigint,
    productid varchar,
    customerid varchar
)
WITH
    (kafka_topic= 'shipments', value_format='json', timestamp='shipment_time');

EOF

log "START BENCHMARK for QUERY 0"
SECONDS=0
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM FILTERED_STREAM AS SELECT
  *
FROM
  ORDERS
WHERE productid='Product_1' or productid='Product_2';
EOF

playground ksqldb wait --max-wait 3600 --source "FILTERED_STREAM"
throughtput "FILTERED_STREAM" "$SECONDS"

log "START BENCHMARK for QUERY 1"
SECONDS=0
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM ENRICHED_O_C AS SELECT
  UNIX_TIMESTAMP() JOINTIME,
  O.ORDERTIME ORDERTIME,
  O.ORDERID ORDERID,
  O.PRODUCTID PRODUCTID,
  O.ORDERUNITS ORDERUNITS,
  O.CUSTOMERID CUSTOMERID,
  CUSTOMERS.FIRSTNAME FIRSTNAME,
  CUSTOMERS.LASTNAME LASTNAME,
  CUSTOMERS.GENDER GENDER,
  CUSTOMERS.RANDOM_DATA RANDOM_DATA,
  CUSTOMERS.ADDRESS ADDRESS
FROM
  ORDERS O
LEFT OUTER JOIN
    CUSTOMERS CUSTOMERS
    ON ((O.CUSTOMERID = CUSTOMERS.CUSTOMERID));
EOF

playground ksqldb wait --max-wait 3600 --source "ENRICHED_O_C"
throughtput "ENRICHED_O_C" "$SECONDS"

SECONDS=0
log "START BENCHMARK for QUERY 2"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM ENRICHED_O_C_P AS SELECT
  UNIX_TIMESTAMP() JOINTIME,
  ORDERTIME,
  ORDERID,
  P.PRODUCTID as PRODUCTID,
  ORDERUNITS,
  CUSTOMERID,
  FIRSTNAME,
  LASTNAME,
  GENDER,
  RANDOM_DATA,
  ADDRESS,
  NAME as ProductName,
  category,
  description
FROM
  ENRICHED_O_C o
LEFT JOIN
  PRODUCTS p
ON O.PRODUCTID = P.PRODUCTID;
EOF

playground ksqldb wait --max-wait 3600 --source "ENRICHED_O_C_P"
throughtput "ENRICHED_O_C_P" "$SECONDS"

SECONDS=0
log "START BENCHMARK for QUERY 3"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM ORDERS_SHIPPED AS SELECT
  UNIX_TIMESTAMP() JOINTIME,
  O.ORDERID O_ORDERID,
  S.ORDERID S_ORDERID,
  S.SHIPMENTID SHIPMENTID,
  O.PRODUCTID PRODUCTID,
  O.CUSTOMERID CUSTOMERID,
  O.ORDERUNITS ORDERUNITS,
  PRODUCTNAME,
  CATEGORY,
  DESCRIPTION,
  FIRSTNAME,
  lastname,
  gender,
  RANDOM_DATA,
  address
FROM
  ENRICHED_O_C_P o
INNER JOIN SHIPMENTS S
  WITHIN 2 HOURS
ON O.ORDERID = S.ORDERID;
EOF

playground ksqldb wait --max-wait 3600 --source "ORDERS_SHIPPED"
throughtput "ORDERS_SHIPPED" "$SECONDS"

SECONDS=0
log "START BENCHMARK for QUERY 4"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE TABLE ORDERPER_PROD_CUST_AGG AS SELECT
  os.PRODUCTID PRODUCTID,
  os.CUSTOMERID CUSTOMERID,
  COUNT(*) COUNTVAL,
  SUM(os.ORDERUNITS) ORDERSUM,
  MIN(UNIX_TIMESTAMP()) MINTIME,
  MAX(UNIX_TIMESTAMP()) MAXTIME,
  MAX(UNIX_TIMESTAMP()) - MIN(UNIX_TIMESTAMP()) TIMEDIFF
FROM
  ORDERS_SHIPPED os
WINDOW TUMBLING ( SIZE 1 MINUTES )
GROUP BY
  os.PRODUCTID, os.CUSTOMERID;
EOF

playground ksqldb wait --max-wait 3600 --source "ORDERPER_PROD_CUST_AGG"
throughtput "ORDERPER_PROD_CUST_AGG" "$SECONDS"
