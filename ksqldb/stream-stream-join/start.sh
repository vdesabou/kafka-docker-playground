#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

log "Create the Streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

CREATE STREAM orders (ID INT KEY, order_ts VARCHAR, total_amount DOUBLE, customer_name VARCHAR)
    WITH (KAFKA_TOPIC='_orders',
          VALUE_FORMAT='AVRO',
          TIMESTAMP='order_ts',
          TIMESTAMP_FORMAT='yyyy-MM-dd''T''HH:mm:ssX',
          PARTITIONS=4);

CREATE STREAM shipments (ID VARCHAR KEY, ship_ts VARCHAR, order_id INT, warehouse VARCHAR)
    WITH (KAFKA_TOPIC='_shipments',
          VALUE_FORMAT='AVRO',
          TIMESTAMP='ship_ts',
          TIMESTAMP_FORMAT='yyyy-MM-dd''T''HH:mm:ssX',
          PARTITIONS=4);

EOF

log "Insert the records"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

INSERT INTO orders (id, order_ts, total_amount, customer_name) VALUES (1, '2019-03-29T06:01:18Z', 133548.84, 'Ricardo Ferreira');
INSERT INTO orders (id, order_ts, total_amount, customer_name) VALUES (2, '2019-03-29T17:02:20Z', 164839.31, 'Tim Berglund');
INSERT INTO orders (id, order_ts, total_amount, customer_name) VALUES (3, '2019-03-29T13:44:10Z', 90427.66, 'Robin Moffatt');
INSERT INTO orders (id, order_ts, total_amount, customer_name) VALUES (4, '2019-03-29T11:58:25Z', 33462.11, 'Viktor Gamov');

INSERT INTO shipments (id, ship_ts, order_id, warehouse) VALUES ('ship-ch83360', '2019-03-31T18:13:39Z', 1, 'UPS');
INSERT INTO shipments (id, ship_ts, order_id, warehouse) VALUES ('ship-xf72808', '2019-03-31T02:04:13Z', 2, 'UPS');
INSERT INTO shipments (id, ship_ts, order_id, warehouse) VALUES ('ship-kr47454', '2019-03-31T20:47:09Z', 3, 'DHL');
EOF

log "The following query will do a left join between the ratings stream and the movies table on the movie id"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT o.id AS order_id,
       TIMESTAMPTOSTRING(o.rowtime, 'yyyy-MM-dd HH:mm:ss', 'UTC') AS order_ts,
       o.total_amount,
       o.customer_name,
       s.id as shipment_id,
       TIMESTAMPTOSTRING(s.rowtime, 'yyyy-MM-dd HH:mm:ss', 'UTC') AS shipment_ts,
       s.warehouse,
       (s.rowtime - o.rowtime) / 1000 / 60 AS ship_time
FROM orders o INNER JOIN shipments s
WITHIN 7 DAYS
ON o.id = s.order_id
EMIT CHANGES
LIMIT 3;

EOF

# This should yield the following output:
# +--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+
# |ORDER_ID            |ORDER_TS            |TOTAL_AMOUNT        |CUSTOMER_NAME       |SHIPMENT_ID         |SHIPMENT_TS         |WAREHOUSE           |SHIP_TIME           |
# +--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+--------------------+
# |1                   |2019-03-29 06:01:18 |133548.84           |Ricardo Ferreira    |ship-ch83360        |2019-03-31 18:13:39 |UPS                 |3612                |
# |2                   |2019-03-29 17:02:20 |164839.31           |Tim Berglund        |ship-xf72808        |2019-03-31 02:04:13 |UPS                 |1981                |
# |3                   |2019-03-29 13:44:10 |90427.66            |Robin Moffatt       |ship-kr47454        |2019-03-31 20:47:09 |DHL                 |33
