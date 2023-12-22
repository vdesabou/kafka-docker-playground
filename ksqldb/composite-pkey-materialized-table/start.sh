#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

# TEST 1 -> STREAM + Materialized View with DOUBLE and INT types
log "Create a stream of transactions"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM my_transactions_stream (transaction STRUCT<customer_id INT,product_id DOUBLE,txn_id INT>, created_at BIGINT, description VARCHAR)
  WITH (kafka_topic='transactions-stream', value_format='AVRO', partitions=1);
EOF

log "Create a materialized view from this stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE TRANSACTIONS_MV
WITH (KAFKA_TOPIC='transactions-mv', PARTITIONS=1,VALUE_FORMAT='avro',KEY_FORMAT='avro')
AS
SELECT
  transaction,
  latest_by_offset(created_at) as created_at,
  latest_by_offset(description) as description
FROM my_transactions_stream
GROUP BY transaction
EMIT CHANGES;
EOF

sleep 5
log "Insert the records to the stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
INSERT INTO MY_TRANSACTIONS_STREAM (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=123, product_id:=10005, txn_id:=500005), 1697188928, 'buying stocks');
INSERT INTO MY_TRANSACTIONS_STREAM (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=123, product_id:=10006, txn_id:=500006), 1697188930, 'second transaction');
INSERT INTO MY_TRANSACTIONS_STREAM (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=140, txn_id:=500007), 1697188940, 'transaction for user 140');
INSERT INTO MY_TRANSACTIONS_STREAM (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=140, product_id:=10005, txn_id:=500008), 1697188950, 'second trx for user 140');
EOF
sleep 5

log "Print the full table"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT * FROM TRANSACTIONS_MV
EMIT CHANGES LIMIT 4;
EOF

log "SELECT with a WHERE CLAUSE using -> and setting all keys fields in where clause"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS_MV
WHERE TRANSACTION->CUSTOMER_ID=123 and TRANSACTION->PRODUCT_ID=10005.0 and TRANSACTION->TXN_ID=500005
EMIT CHANGES LIMIT 1;
EOF
# Expected output:
# +-----+-----+-----+
# |TRANS|CREAT|DESCR|
# |ACTIO|ED_AT|IPTIO|
# |N    |     |N    |
# +-----+-----+-----+
# |{CUST|16971|buyin|
# |OMER_|88928|g sto|
# |ID=12|     |cks  |
# |3, PR|     |     |
# |ODUCT|     |     |
# |_ID=1|     |     |
# |0005.|     |     |
# |0, TX|     |     |
# |N_ID=|     |     |
# |50000|     |     |
# |5}   |     |     |

log "PUSH Query: SELECT with a WHERE CLAUSE using -> and setting one key field as IS NULL"
log "This push query works well and return the output"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS_MV
WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->TXN_ID=500007 and TRANSACTION->PRODUCT_ID IS NULL
EMIT CHANGES LIMIT 1;
EOF

log "Pull Query: SELECT with a WHERE CLAUSE using -> and setting one key field as IS NULL"
log "This pull query will fail, as this is not supported by ksqlDB"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS_MV
WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->TXN_ID=500007 and TRANSACTION->PRODUCT_ID IS NULL;
EOF
# Expected output:
# ksql> Unsupported expression in WHERE clause: (TRANSACTION->PRODUCT_ID IS NULL).  See https://cnfl.io/queries for more info.
# Add EMIT CHANGES if you intended to issue a push query.
# Pull queries require a WHERE clause that:
#  - includes a key equality expression, e.g. `SELECT * FROM X WHERE <key-column> = Y;`.
#  - in the case of a multi-column key, is a conjunction of equality expressions that cover all key columns.
#  - to support range expressions, e.g.,  SELECT * FROM X WHERE <key-column> < Y;`, range scans need to be enabled by setting ksql.query.pull.range.scan.enabled=true
# If more flexible queries are needed, , table scans can be enabled by setting ksql.query.pull.table.scan.enabled=true.

# log "SELECT with a WHERE clause using STRUCT"
#NOT WORKING --> NO OUTPUT and hanging
# timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
# SET 'auto.offset.reset' = 'earliest';
#
# SELECT * FROM TRANSACTIONS_MV
# WHERE TRANSACTION =  struct(CUSTOMER_ID:=123, PRODUCT_ID:=10005.0, TXN_ID:=500005);
#
# EOF

# TEST 2 -> STREAM + Materialized View
log "Create STREAM and TABLE"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM my_transactions_stream2 (transaction STRUCT<customer_id VARCHAR,product_id VARCHAR,txn_id VARCHAR>, created_at BIGINT, description VARCHAR)
  WITH (kafka_topic='transactions-stream2', value_format='AVRO', partitions=1);

CREATE TABLE TRANSACTIONS_MV2
  WITH (KAFKA_TOPIC='transactions-mv2', PARTITIONS=1,VALUE_FORMAT='avro',KEY_FORMAT='avro')
  AS
  SELECT
    transaction,
    latest_by_offset(created_at) as created_at,
    latest_by_offset(description) as description
  FROM my_transactions_stream2
  GROUP BY transaction
  EMIT CHANGES;
EOF
sleep 5

log "Insert the records to the stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
INSERT INTO MY_TRANSACTIONS_STREAM2 (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:='123', product_id:='10005', txn_id:='500005'), 1697188928, 'buying stocks');
INSERT INTO MY_TRANSACTIONS_STREAM2 (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:='123', product_id:='10006', txn_id:='500006'), 1697188930, 'second transaction');
INSERT INTO MY_TRANSACTIONS_STREAM2 (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:='140', txn_id:='500007'), 1697188940, 'transaction for user 140');
INSERT INTO MY_TRANSACTIONS_STREAM2 (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:='140', product_id:='10005', txn_id:='500008'), 1697188950, 'second trx for user 140');
EOF
sleep 5

log "Print the full table"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT * FROM TRANSACTIONS_MV2
EMIT CHANGES LIMIT 4;

-- we can query the materialized view with a STRUCT() clause
SELECT * FROM TRANSACTIONS_MV2
WHERE TRANSACTION = STRUCT(CUSTOMER_ID:='123', PRODUCT_ID:='10005', TXN_ID:='500005');
EOF

# One record has the field product_id that is null
# |{CUST|16971|trans|
# |OMER_|88940|actio|
# |ID=14|     |n for|
# |0, PR|     | user|
# |ODUCT|     | 140 |
# |_ID=n|     |     |
# |ull, |     |     |
# |TXN_I|     |     |
# |D=500|     |     |
# |007} |     |     |

log "With ksqlDB, we can't query the record that the one of his composite field set as NULL. (i.e: product_id is null)"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT * FROM TRANSACTIONS_MV2
WHERE TRANSACTION = STRUCT(CUSTOMER_ID:='140', PRODUCT_ID:=null, TXN_ID:='500007');
EOF


# TEST 3 -> TABLE
log "Create the ksqlDB table"
log "The Primary key will be a STRUCT<>"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE TRANSACTIONS (
  transaction STRUCT<customer_id INT,
                  product_id DOUBLE,
                  txn_id INT> PRIMARY KEY,
  created_at BIGINT,
  description VARCHAR
) WITH (
  KAFKA_TOPIC='transactions',
  PARTITIONS=1,
  VALUE_FORMAT='avro',
  KEY_FORMAT='avro'
);
EOF

log "Insert the records to this table"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

INSERT INTO TRANSACTIONS (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=123, product_id:=10005, txn_id:=500005), 1697188928, 'buying stocks');
INSERT INTO TRANSACTIONS (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=123, product_id:=10006, txn_id:=500006), 1697188930, 'second transaction');
INSERT INTO TRANSACTIONS (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=140, txn_id:=500007), 1697188940, 'transaction for user 140');
INSERT INTO TRANSACTIONS (TRANSACTION, CREATED_AT, DESCRIPTION) VALUES (STRUCT(customer_id:=140, product_id:=10005, txn_id:=500008), 1697188950, 'second trx for user 140');

EOF

log "Print the full table"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS
EMIT CHANGES LIMIT 4;

EOF

log "SELECT with a WHERE CLAUSE using ->"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS
WHERE TRANSACTION->CUSTOMER_ID=123 and TRANSACTION->PRODUCT_ID=10005.0 and TRANSACTION->TXN_ID=500005
EMIT CHANGES LIMIT 1;

EOF

# expected output
# +-----+-----+-----+
# |TRANS|CREAT|DESCR|
# |ACTIO|ED_AT|IPTIO|
# |N    |     |N    |
# +-----+-----+-----+
# |{CUST|16971|buyin|
# |OMER_|88928|g sto|
# |ID=12|     |cks  |
# |3, PR|     |     |
# |ODUCT|     |     |
# |_ID=1|     |     |
# |0005.|     |     |
# |0, TX|     |     |
# |N_ID=|     |     |
# |50000|     |     |
# |5}   |     |     |
# Limit Reached

log "SELECT with a WHERE CLAUSE on a NULL field using -> and CAST(null AS STRING)"
log "It will fail. CAST(null AS STRING) is not supported by ksqlDB "
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS
WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->PRODUCT_ID  = CAST(null AS STRING) and TRANSACTION->TXN_ID=500007
EMIT CHANGES LIMIT 1;
EOF

# expected exception:
# Error in WHERE expression: Cannot compare TRANSACTION->PRODUCT_ID (DOUBLE) to CAST(null AS STRING) (STRING) with EQUAL.
# Statement: (TRANSACTION->PRODUCT_ID = CAST(null AS STRING))
# Statement: (((TRANSACTION->CUSTOMER_ID = 140) AND (TRANSACTION->PRODUCT_ID = CAST(null AS STRING))) AND (TRANSACTION->TXN_ID = 500007))


log "SELECT with a WHERE clause using STRUCT"
log "NOT WORKING --> NO OUTPUT and hanging"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS
WHERE TRANSACTION =  STRUCT(CUSTOMER_ID:=123, PRODUCT_ID:=10005.0, TXN_ID:=500005)
EMIT CHANGES LIMIT 1;

EOF

# Conclusion:
# You need to use add each key in the WHERE clause with `->`. For example:
# SELECT * FROM TRANSACTIONS
# WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->PRODUCT_ID IS NULL and TRANSACTION->TXN_ID=500007
