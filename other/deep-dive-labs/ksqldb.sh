#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-ksqldb

lab_require_plaintext
export ENABLE_KSQLDB=true
# with the processing log (KSQL_PROCESSING_LOG stream), like ksqldb/manage-deserialization-errors
playground start-environment --environment plaintext --docker-compose-override-file "${DIR}/docker-compose.plaintext.ksqldb.yml"

log "Step 1: a stream, a table built from it, in one session"
lab_run playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM ORDERS (ID INT KEY, PRODUCT VARCHAR, QUANTITY INT) WITH (KAFKA_TOPIC = 'orders', VALUE_FORMAT = 'JSON', PARTITIONS = 1);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (1, 'laptop', 1);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (2, 'phone', 2);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (3, 'laptop', 3);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (4, 'tablet', 4);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (5, 'phone', 5);
INSERT INTO ORDERS (ID, PRODUCT, QUANTITY) VALUES (6, 'laptop', 6);
CREATE TABLE ORDERS_BY_PRODUCT AS
  SELECT PRODUCT, COUNT(*) AS NB_ORDERS, SUM(QUANTITY) AS TOTAL_QUANTITY
  FROM ORDERS GROUP BY PRODUCT EMIT CHANGES;
EOF
lab_expect_exit 0
lab_expect_contains "🧮 Running ksqlDB statements in ksqldb-cli container (ksqlDB"
lab_expect_contains "Successfully changed local property 'auto.offset.reset' to 'earliest'."
lab_expect_contains "Stream created"
lab_expect_contains "Created query with ID CTAS_ORDERS_BY_PRODUCT_"

log "Step 2: wait for the query instead of a sleep"
lab_run playground ksqldb wait --source ORDERS_BY_PRODUCT
lab_expect_exit 0
lab_expect_contains "✅ the queries writing to ORDERS_BY_PRODUCT are RUNNING and have no lag"

log "Step 3: pull query vs push query"
lab_run playground ksqldb sql << 'EOF'
SELECT * FROM ORDERS_BY_PRODUCT WHERE PRODUCT = 'laptop';
EOF
lab_expect_exit 0
lab_expect_contains "|PRODUCT"
lab_expect_equals "$(grep -c -E '^\|laptop +\|3 +\|10 +\|' <<< "$LAB_OUTPUT")" "1" "the pull query returns laptop, 3 orders, quantity 10"
lab_run playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
SELECT ID, PRODUCT FROM ORDERS EMIT CHANGES LIMIT 3;
EOF
lab_expect_exit 0
lab_expect_contains "Limit Reached"
lab_expect_contains "Query terminated"

log "Step 4: SET only lasts for the call"
lab_run playground ksqldb sql --query-timeout 10 << 'EOF'
SELECT ID, PRODUCT FROM ORDERS EMIT CHANGES;
EOF
lab_expect_exit 0
lab_expect_not_contains "|laptop" "no row: without SET 'auto.offset.reset' = 'earliest', a push query reads from the end"
lab_run playground ksqldb sql << 'EOF'
CREATE STREAM BIG_ORDERS AS SELECT * FROM ORDERS WHERE QUANTITY >= 3 EMIT CHANGES;
EOF
lab_expect_exit 0
lab_expect_contains "Created query with ID CSAS_BIG_ORDERS_"
lab_run playground ksqldb wait --source BIG_ORDERS
lab_expect_exit 0
lab_expect_contains "has not committed any offset after 20s: nothing to process from where it started"
lab_expect_contains "are RUNNING without lag, but CSAS_BIG_ORDERS_" "the last line says that the query processed nothing"
lab_expect_not_contains "✅ the queries writing to BIG_ORDERS" "no all-clear for a query that processed nothing"
lab_run playground topic get-number-records --topic BIG_ORDERS
lab_expect_equals "$(tail -1 <<< "$LAB_OUTPUT")" "0" "BIG_ORDERS is empty: its CREATE was sent without SET 'auto.offset.reset' = 'earliest'"

log "Step 5: list and describe"
lab_run playground ksqldb list
lab_expect_exit 0
lab_expect_contains "TYPE NAME TOPIC KEY FORMAT VALUE FORMAT WINDOWED"
lab_expect_contains "STREAM ORDERS orders KAFKA JSON false"
lab_expect_contains "TABLE ORDERS_BY_PRODUCT ORDERS_BY_PRODUCT KAFKA JSON false"
lab_expect_contains "QUERY ID STATE TYPE SINKS SINK TOPICS"
lab_expect_contains "RUNNING PERSISTENT ORDERS_BY_PRODUCT ORDERS_BY_PRODUCT"
lab_run playground ksqldb describe --source ORDERS_BY_PRODUCT
lab_expect_exit 0
lab_expect_contains "🧮 TABLE ORDERS_BY_PRODUCT: topic ORDERS_BY_PRODUCT (1 partitions, replication 1), key format KAFKA, value format JSON"
lab_expect_contains "FIELD TYPE KEY"
lab_expect_contains "PRODUCT STRING 🔑"
lab_expect_contains "✍️ Queries writing to ORDERS_BY_PRODUCT"
lab_expect_contains "📊 Statistics (sum over the ksqlDB servers)"
lab_run bash -c "playground ksqldb list --json | jq -r '.queries[] | \"\(.id) \(.state)\"'"
lab_expect_exit 0
lab_expect_contains "RUNNING"

log "Step 6: a record that can't be deserialized, and the processing log"
lab_run playground topic produce -t orders --value 'not json' --value-format raw
lab_expect_exit 0
lab_run playground topic produce -t orders --value '{"PRODUCT": "phone", "QUANTITY": 8}' --value-format raw
lab_expect_exit 0
# a valid value, but the key is the string "9": ID INT KEY in KAFKA format expects a 4 bytes integer
lab_run playground topic produce -t orders --key 9 --value '{"PRODUCT": "phone", "QUANTITY": 100}' --value-format raw
lab_expect_exit 0
lab_run playground ksqldb wait --source ORDERS_BY_PRODUCT
lab_expect_exit 0
lab_run playground ksqldb sql << 'EOF'
SELECT * FROM ORDERS_BY_PRODUCT WHERE PRODUCT = 'phone';
EOF
lab_expect_exit 0
lab_expect_equals "$(grep -c -E '^\|phone +\|3 +\|15 +\|' <<< "$LAB_OUTPUT")" "1" "phone: the record without key is counted, the bad value and the bad key are skipped"
lab_run playground ksqldb describe --source ORDERS
lab_expect_exit 0
lab_expect_contains "⚠️ Errors"
lab_expect_contains "consumer-failed-messages: 4.0" "2 bad records x 2 queries reading ORDERS"
lab_expect_contains "🎓 the records that failed are in the processing log: SELECT * FROM KSQL_PROCESSING_LOG EMIT CHANGES LIMIT 10;"
lab_run playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
SELECT LOGGER, MESSAGE->DESERIALIZATIONERROR->ERRORMESSAGE AS ERROR,
       ENCODE(MESSAGE->DESERIALIZATIONERROR->RECORDB64, 'base64', 'utf8') AS RECORD
FROM KSQL_PROCESSING_LOG EMIT CHANGES LIMIT 4;
EOF
lab_expect_exit 0
lab_expect_contains "Failed to deserialize value from topic: orders"
lab_expect_contains "not json"
lab_expect_contains "Error deserializing KAFKA message from topic: orders" "the key error doesn't say key"
lab_run playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
SELECT MESSAGE->DESERIALIZATIONERROR->CAUSE AS CAUSE
FROM KSQL_PROCESSING_LOG
WHERE MESSAGE->DESERIALIZATIONERROR->ERRORMESSAGE LIKE 'Error deserializing KAFKA%'
EMIT CHANGES LIMIT 1;
EOF
lab_expect_exit 0
lab_expect_contains "[Size of data received by IntegerDeserializer is not 4]"

log "Step 7: tombstones on a table"
lab_run playground ksqldb sql << 'EOF'
SET 'auto.offset.reset' = 'earliest';
CREATE SOURCE TABLE PRODUCTS (ID VARCHAR PRIMARY KEY, NAME VARCHAR) WITH (KAFKA_TOPIC = 'products', VALUE_FORMAT = 'JSON', PARTITIONS = 1);
EOF
lab_expect_exit 0
lab_expect_contains "Created query with ID CST_PRODUCTS_" "a source table is materialized by a query"
lab_run playground topic produce -t products --key p1 --value '{"NAME": "laptop"}' --value-format raw
lab_run playground topic produce -t products --key p2 --value '{"NAME": "phone"}' --value-format raw
lab_run playground ksqldb wait --source PRODUCTS
lab_expect_exit 0
lab_expect_not_contains "no query writes to PRODUCTS" "ksqldb wait finds the CST_ query of the source table"
lab_expect_contains "✅ the queries writing to PRODUCTS are RUNNING and have no lag"
lab_run playground ksqldb sql --ignore-errors << 'EOF'
INSERT INTO PRODUCTS (ID, NAME) VALUES ('p3', 'tablet');
SELECT * FROM PRODUCTS;
EOF
lab_expect_exit 0
lab_expect_contains "⚠️ 1 ksqlDB statement(s) failed (ignored, --ignore-errors is set)"
lab_expect_equals "$(grep -c -E '^\|p[12] +\|' <<< "$LAB_OUTPUT")" "2" "the source table has p1 and p2"
lab_run playground topic produce -t products --tombstone --key p1
lab_expect_exit 0
lab_run playground ksqldb wait --source PRODUCTS
lab_expect_exit 0
lab_expect_contains "✅ the queries writing to PRODUCTS are RUNNING and have no lag"
lab_run playground ksqldb sql << 'EOF'
SELECT * FROM PRODUCTS;
EOF
lab_expect_exit 0
lab_expect_equals "$(grep -c -E '^\|p1 +\|' <<< "$LAB_OUTPUT")" "0" "the tombstone deleted p1"
lab_expect_equals "$(grep -c -E '^\|p2 +\|' <<< "$LAB_OUTPUT")" "1" "p2 is still there"

lab_run playground ksqldb sql --ignore-errors << 'EOF'
CREATE TABLE PRODUCTS_PLAIN (ID VARCHAR PRIMARY KEY, NAME VARCHAR) WITH (KAFKA_TOPIC = 'products', VALUE_FORMAT = 'JSON');
SELECT * FROM PRODUCTS_PLAIN;
EOF
lab_expect_exit 0
lab_expect_contains "Table created"
lab_expect_contains "The \`PRODUCTS_PLAIN\` table isn't queryable. To derive a queryable table, you can do 'CREATE TABLE QUERYABLE_PRODUCTS_PLAIN AS SELECT * FROM PRODUCTS_PLAIN'."
lab_expect_contains "⚠️ 1 ksqlDB statement(s) failed (ignored, --ignore-errors is set)" "a plain CREATE TABLE is not materialized: no pull query"

log "Step 8: the classic mistakes"
lab_run playground ksqldb sql < /dev/null
lab_expect_exit 1
lab_expect_contains "❌ no ksqlDB statements: pass them on stdin (heredoc) or with --file"
lab_run playground ksqldb sql << 'EOF'
CREATE STREAM ORDERS (ID INT KEY, PRODUCT VARCHAR) WITH (KAFKA_TOPIC = 'orders', VALUE_FORMAT = 'JSON');
SELECT * FROM NOPE EMIT CHANGES LIMIT 1;
SHOW STREAMS;
EOF
lab_expect_exit 1
lab_expect_contains "❌ 2 ksqlDB statement(s) failed (the other statements were run):"
lab_expect_contains "🎓 add --ignore-errors when the failure is expected"
lab_expect_contains "KSQL_PROCESSING_LOG" "SHOW STREAMS still ran after the failures"
lab_run playground ksqldb sql --max-wait 20 << 'EOF'
SELECT * FROM ORDERS EMIT CHANGES;
EOF
lab_expect_exit 1
lab_expect_contains "⏱️ the ksql cli was stopped after 20s: a push query (EMIT CHANGES) never ends without a LIMIT"
lab_expect_contains "add LIMIT <n> to the query, set --query-timeout, or increase --max-wait"

log "✅ all the outputs of the page are as expected"
