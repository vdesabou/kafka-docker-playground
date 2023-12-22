#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

log "Create the ksqlDB streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM TRANSACTION_STREAM (
	      id VARCHAR,
              transaction STRUCT<num_shares INT,
             	                  amount DOUBLE,
             	                  txn_ts VARCHAR,
             	                  customer STRUCT<first_name VARCHAR,
             	                                  last_name VARCHAR,
             	                                  id INT,
             	                                  email VARCHAR>,
                                   company STRUCT<name VARCHAR,
                                                  ticker VARCHAR,
                                                  id VARCHAR,
                                                  address VARCHAR>>)
 WITH (KAFKA_TOPIC='financial_txns',
       VALUE_FORMAT='JSON',
       PARTITIONS=1);
EOF

log "Produce records to financial_txns"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic financial_txns << EOF
{ "id": "1", "transaction": { "num_shares": 50000, "amount": 50044568.89, "txn_ts": "2020-11-18 02:31:43", "customer": { "first_name": "Jill", "last_name": "Smith", "id": 1234567, "email": "jsmith@gmail.com" }, "company": { "name": "ACME Corp", "ticker": "ACMC", "id": "ACME837275222752952", "address": "Anytown USA, 333333" } } }
{ "id": "2", "transaction": { "num_shares": 30000, "amount": 5004.89, "txn_ts": "2020-11-18 02:35:43", "customer": { "first_name": "Art", "last_name": "Vandeley", "id": 8976612, "email": "avendleay@gmail.com" }, "company": { "name": "Imports Corp", "ticker": "IMPC", "id": "IMPC88875222752952", "address": "Anytown USA, 333333" } } }
{ "id": "3", "transaction": { "num_shares": 3000000, "amount": 600044568.89, "txn_ts": "2020-11-18 02:36:43", "customer": { "first_name": "John", "last_name": "England", "id": 456321, "email": "je@gmail.com" }, "company": { "name": "Hechinger", "ticker": "HECH", "id": "HECH8333785222752952", "address": "Anytown USA, 333333" } } }
{ "id": "4", "transaction": { "num_shares": 10000, "amount": 80044.89, "txn_ts": "2020-11-18 02:37:43", "customer": { "first_name": "Fred", "last_name": "Pym", "id": 333567, "email": "fjone@gmail.com" }, "company": { "name": "PymTech", "ticker": "PYMT", "id": "PYME837275222714197419202020", "address": "Anytown USA, 333333" } } }
EOF

# Wait for the stream to be initialized
sleep 5

log "We can query this nested JSON"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
-- we can adjust the column width so we can easily see the results of the query
SET CLI COLUMN-WIDTH 10

SELECT
    TRANSACTION->num_shares AS SHARES,
    TRANSACTION->CUSTOMER->ID as CUST_ID,
    TRANSACTION->COMPANY->TICKER as SYMBOL
FROM
    TRANSACTION_STREAM
EMIT CHANGES
LIMIT 4;
EOF

# This query should produce the following output:
# +----------+----------+----------+
# |SHARES    |CUST_ID   |SYMBOL    |
# +----------+----------+----------+
# |50000     |1234567   |ACMC      |
# |30000     |8976612   |IMPC      |
# |3000000   |456321    |HECH      |
# |10000     |333567    |PYMT      |
# Limit Reached
# Query terminated

log "We can create a STREAM based on this query"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM FINANCIAL_REPORTS AS
    SELECT
    TRANSACTION->num_shares AS SHARES,
    TRANSACTION->CUSTOMER->ID as CUST_ID,
    TRANSACTION->COMPANY->TICKER as SYMBOL
FROM
    TRANSACTION_STREAM;
EOF

sleep 5
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT * FROM FINANCIAL_REPORTS;
EOF
