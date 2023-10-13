#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

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

log "SELECT with a WHERE CLAUSE using ->"
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

# log "SELECT with a WHERE clause using STRUCT"
#NOT WORKING --> NO OUTPUT and hanging
# timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
# SET 'auto.offset.reset' = 'earliest';
#
# SELECT * FROM TRANSACTIONS_MV
# WHERE TRANSACTION =  struct(CUSTOMER_ID:=123, PRODUCT_ID:=10005.0, TXN_ID:=500005)
# EMIT CHANGES LIMIT 1;
#
# EOF


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

log "SELECT with a WHERE CLAUSE on a NULL field using ->"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS
WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->PRODUCT_ID IS NULL and TRANSACTION->TXN_ID=500007
EMIT CHANGES LIMIT 1;

EOF

# expected output:
# +-----+-----+-----+
# |TRANS|CREAT|DESCR|
# |ACTIO|ED_AT|IPTIO|
# |N    |     |N    |
# +-----+-----+-----+
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

log "SELECT with a WHERE clause using STRUCT"
#NOT WORKING --> NO OUTPUT and hanging
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM TRANSACTIONS
WHERE TRANSACTION =  struct(CUSTOMER_ID:=123, PRODUCT_ID:=10005.0, TXN_ID:=500005)
EMIT CHANGES LIMIT 1;

EOF

# Conclusion:
# You need to use add each key in the WHERE clause with `->`. For example:
# SELECT * FROM TRANSACTIONS
# WHERE TRANSACTION->CUSTOMER_ID=140 and TRANSACTION->PRODUCT_ID IS NULL and TRANSACTION->TXN_ID=500007
