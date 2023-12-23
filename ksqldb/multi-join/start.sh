#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Create the Stream and the Table"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

CREATE TABLE customers (customerid STRING PRIMARY KEY, customername STRING)
    WITH (KAFKA_TOPIC='customers',
          VALUE_FORMAT='json',
          PARTITIONS=1);

CREATE TABLE items (itemid STRING PRIMARY KEY, itemname STRING)
    WITH (KAFKA_TOPIC='items',
          VALUE_FORMAT='json',
          PARTITIONS=1);

CREATE STREAM orders (orderid STRING KEY, customerid STRING, itemid STRING, purchasedate STRING)
    WITH (KAFKA_TOPIC='orders',
          VALUE_FORMAT='json',
          PARTITIONS=1);

EOF

log "Insert the records"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

INSERT INTO customers VALUES ('1', 'Adrian Garcia');
INSERT INTO customers VALUES ('2', 'Robert Miller');
INSERT INTO customers VALUES ('3', 'Brian Smith');

INSERT INTO items VALUES ('101', 'Television 60-in');
INSERT INTO items VALUES ('102', 'Laptop 15-in');
INSERT INTO items VALUES ('103', 'Speakers');

INSERT INTO orders VALUES ('abc123', '1', '101', '2020-05-01');
INSERT INTO orders VALUES ('abc345', '1', '102', '2020-05-01');
INSERT INTO orders VALUES ('abc678', '2', '101', '2020-05-01');
INSERT INTO orders VALUES ('abc987', '3', '101', '2020-05-03');
INSERT INTO orders VALUES ('xyz123', '2', '103', '2020-05-03');
INSERT INTO orders VALUES ('xyz987', '2', '102', '2020-05-05');

EOF

log "Create a stream that produces orders enriched with data from the customers and items tables"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM orders_enriched AS
  SELECT customers.customerid AS customerid, customers.customername AS customername,
         orders.orderid, orders.purchasedate,
         items.itemid, items.itemname
  FROM orders
  LEFT JOIN customers on orders.customerid = customers.customerid
  LEFT JOIN items on orders.itemid = items.itemid;

EOF

# Wait for the stream to be initialized
sleep 5

log "View the result by selecting the values from our new enriched orders stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM ORDERS_ENRICHED EMIT CHANGES LIMIT 6;
EOF

# The output should look similar to:
# +-----------------+-----------------+-----------------+-----------------+-----------------+-----------------+
# |ITEMS_ITEMID     |CUSTOMERID       |CUSTOMERNAME     |ORDERID          |PURCHASEDATE     |ITEMNAME         |
# +-----------------+-----------------+-----------------+-----------------+-----------------+-----------------+
# |101              |1                |Adrian Garcia    |abc123           |2020-05-01       |Television 60-in |
# |102              |1                |Adrian Garcia    |abc345           |2020-05-01       |Laptop 15-in     |
# |101              |2                |Robert Miller    |abc678           |2020-05-01       |Television 60-in |
# |101              |3                |Brian Smith      |abc987           |2020-05-03       |Television 60-in |
# |103              |2                |Robert Miller    |xyz123           |2020-05-03       |Speakers         |
# |102              |2                |Robert Miller    |xyz987           |2020-05-05       |Laptop 15-in     |
# Limit Reached
# Query terminated
