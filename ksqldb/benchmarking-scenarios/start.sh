#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NOW="$(date +%s)000"
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/orders-template.avro > ${DIR}/schemas/orders.avro
sed -e "s|:NOW:|$NOW|g" \
    ${DIR}/schemas/shipments-template.avro > ${DIR}/schemas/shipments.avro

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
      http://localhost:8083/connectors/datagen-orders/config | jq

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
                "iterations": "8000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/shipments.avro"
            }' \
      http://localhost:8083/connectors/datagen-shipments/config | jq

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
      http://localhost:8083/connectors/datagen-products/config | jq

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
      http://localhost:8083/connectors/datagen-customers/config | jq

wait_for_datagen_connector_to_inject_data "customers" "10"

log "Create the ksqlDB tables and streams"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

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
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM FILTERED_STREAM AS SELECT
  *
FROM
  ORDERS
WHERE productid='Product_1' or productid='Product_2';
EOF

wait_for_all_streams_to_finish "FILTERED_STREAM" ""

totalmessages=$(curl -s -X "POST" "http://localhost:8088/ksql" \
    -H "Accept: application/vnd.ksql.v1+json" \
    -d $"{
  \"ksql\": \"DESCRIBE EXTENDED FILTERED_STREAM;\",
  \"streamsProperties\": {}
}" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
throughput=$(echo $((totalmessages / SECONDS)))
log "Processed $totalmessages messages. Took $SECONDS seconds. Throughput=$throughput msg/s"

log "START BENCHMARK for QUERY 1"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

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

wait_for_all_streams_to_finish "ENRICHED_O_C" ""

totalmessages=$(curl -s -X "POST" "http://localhost:8088/ksql" \
    -H "Accept: application/vnd.ksql.v1+json" \
    -d $"{
  \"ksql\": \"DESCRIBE EXTENDED ENRICHED_O_C;\",
  \"streamsProperties\": {}
}" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
throughput=$(echo $((totalmessages / SECONDS)))
log "Processed $totalmessages messages. Took $SECONDS seconds. Throughput=$throughput msg/s"


SECONDS=0
log "START BENCHMARK for QUERY 2"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

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

wait_for_all_streams_to_finish "ENRICHED_O_C_P" ""

totalmessages=$(curl -s -X "POST" "http://localhost:8088/ksql" \
    -H "Accept: application/vnd.ksql.v1+json" \
    -d $"{
  \"ksql\": \"DESCRIBE EXTENDED ENRICHED_O_C_P;\",
  \"streamsProperties\": {}
}" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
throughput=$(echo $((totalmessages / SECONDS)))
log "Processed $totalmessages messages. Took $SECONDS seconds. Throughput=$throughput msg/s"

SECONDS=0
log "START BENCHMARK for QUERY 3"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

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

wait_for_all_streams_to_finish "ORDERS_SHIPPED" ""

totalmessages=$(curl -s -X "POST" "http://localhost:8088/ksql" \
    -H "Accept: application/vnd.ksql.v1+json" \
    -d $"{
  \"ksql\": \"DESCRIBE EXTENDED ORDERS_SHIPPED;\",
  \"streamsProperties\": {}
}" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
throughput=$(echo $((totalmessages / SECONDS)))
log "Processed $totalmessages messages. Took $SECONDS seconds. Throughput=$throughput msg/s"

SECONDS=0
log "START BENCHMARK for QUERY 4"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

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

wait_for_all_streams_to_finish "ORDERPER_PROD_CUST_AGG" ""

totalmessages=$(curl -s -X "POST" "http://localhost:8088/ksql" \
    -H "Accept: application/vnd.ksql.v1+json" \
    -d $"{
  \"ksql\": \"DESCRIBE EXTENDED ORDERPER_PROD_CUST_AGG;\",
  \"streamsProperties\": {}
}" | jq -r '.[].sourceDescription.statistics' | grep -Eo '(^|\s)total-messages:\s*\d*\.*\d*' | cut -d":" -f 2 | sed 's/ //g')
throughput=$(echo $((totalmessages / SECONDS)))
log "Processed $totalmessages messages. Took $SECONDS seconds. Throughput=$throughput msg/s"
