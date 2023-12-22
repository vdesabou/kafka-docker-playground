#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

log "Create the transaction stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
-- Create the stream of transactions
CREATE STREAM transactions (
  CUSTOMER_ID BIGINT,
  TIMESTAMP VARCHAR,
  CARD_TYPE VARCHAR,
  AMOUNT BIGINT,
  IP_ADDRESS VARCHAR,
  TRANSACTION_ID VARCHAR
) WITH (
  KAFKA_TOPIC = 'transactions',
  VALUE_FORMAT = 'JSON',
  PARTITIONS = 1
);

-- Create the customer view tables
CREATE TABLE customers (
  ID BIGINT PRIMARY KEY,
  FIRST_NAME VARCHAR,
  LAST_NAME VARCHAR,
  EMAIL VARCHAR
) WITH (
  KAFKA_TOPIC = 'customers',
  VALUE_FORMAT = 'JSON',
  PARTITIONS = 1
);

EOF

log "Insert records to the table and stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

-- Insert customers data
INSERT INTO customers (id, first_name, last_name, email) VALUES (6011000990139424, 'Janice', 'Smith', 'jsmith@mycompany.com');
INSERT INTO customers (id, first_name, last_name, email) VALUES (3530111333300000, 'George', 'Mall', 'gmall@mycompany.com');

-- Insert transaction
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (6011000990139424, '2023-09-23T10:50:00.000Z', 'visa', 54299, '192.168.44.1', '3985757');
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (6011000990139424, '2023-09-23T10:50:01.000Z', 'visa', 61148, '192.168.44.1', '8028435');
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (3530111333300000, '2023-09-23T10:50:00.000Z', 'mastercard', 1031, '192.168.101.3', '1695780');
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (3530111333300000, '2023-09-23T10:50:00.000Z', 'mastercard', 537, '192.168.101.3', '1695780');
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (6011000990139424, '2023-09-25T11:20:00.000Z', 'mastercard', 12399, '192.168.44.1', '23459876');
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (6011000990139424, '2023-09-25T13:30:01.000Z', 'visa', 1248, '192.168.44.1', '4598743');
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (3530111333300000, '2023-09-25T15:00:00.000Z', 'visa', 4631, '192.168.101.3', '7459436');
INSERT INTO transactions (customer_id, timestamp, card_type, amount, ip_address, transaction_id) VALUES (3530111333300000, '2023-09-26T09:00:00.000Z', 'visa', 7937, '192.168.101.3', '9874641');

EOF

sleep 10

log "Get the last 3 transaction events for each customer"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE TABLE last_3_transactions_by_customer_id AS
SELECT customer_id,
REDUCE(
  TOPK(
    concat(
      cast(rowtime as string),
      concat('_',cast(amount as string))
    ),
  3), 0, (s,x) => cast(s as int) + cast(substring(x,instr(x,'_') + 1) as int)
) payment_sum
FROM transactions
GROUP BY customer_id EMIT CHANGES;

EOF

sleep 15

log "We can query this aggregation and join with the customer details"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE TABLE last_3_transactions_by_customer_id_enriched AS
SELECT customer_id, first_name, last_name, email, payment_sum as last_3_payment_sum
FROM last_3_transactions_by_customer_id
JOIN customers ON customers.id = last_3_transactions_by_customer_id.customer_id
EMIT CHANGES;

EOF

sleep 15

timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM last_3_transactions_by_customer_id_enriched;
EOF

# Expected output:
# ksql> +-----+-----+-----+-----+-----+
# |CUSTO|FIRST|LAST_|EMAIL|LAST_|
# |MER_I|_NAME|NAME |     |3_PAY|
# |D    |     |     |     |MENT_|
# |     |     |     |     |SUM  |
# +-----+-----+-----+-----+-----+
# |35301|Georg|Mall |gmall|13105|
# |11333|e    |     |@myco|     |
# |30000|     |     |mpany|     |
# |0    |     |     |.com |     |
# |60110|Janic|Smith|jsmit|74795|
# |00990|e    |     |h@myc|     |
# |13942|     |     |ompan|     |
# |4    |     |     |y.com|     |
# Query terminated
