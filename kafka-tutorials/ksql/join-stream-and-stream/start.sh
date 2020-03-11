#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../../scripts/utils.sh
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

log "Invoke manual steps"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

CREATE STREAM orders (ROWKEY INT KEY, order_ts VARCHAR, total_amount DOUBLE, customer_name VARCHAR)
    WITH (KAFKA_TOPIC='_orders',
          VALUE_FORMAT='AVRO',
          TIMESTAMP='order_ts',
          TIMESTAMP_FORMAT='yyyy-MM-dd''T''HH:mm:ssX',
          PARTITIONS=4);

CREATE STREAM shipments (shipment_id VARCHAR, ship_ts VARCHAR, order_id INT, warehouse VARCHAR)
    WITH (KAFKA_TOPIC='_shipments',
          VALUE_FORMAT='AVRO',
          TIMESTAMP='ship_ts',
          TIMESTAMP_FORMAT='yyyy-MM-dd''T''HH:mm:ssX',
          PARTITIONS=4);

INSERT INTO orders (rowkey, order_ts, total_amount, customer_name) VALUES (1, '2019-03-29T06:01:18Z', 133548.84, 'Ricardo Ferreira');
INSERT INTO orders (rowkey, order_ts, total_amount, customer_name) VALUES (2, '2019-03-29T17:02:20Z', 164839.31, 'Tim Berglund');
INSERT INTO orders (rowkey, order_ts, total_amount, customer_name) VALUES (3, '2019-03-29T13:44:10Z', 90427.66, 'Robin Moffatt');
INSERT INTO orders (rowkey, order_ts, total_amount, customer_name) VALUES (4, '2019-03-29T11:58:25Z', 33462.11, 'Viktor Gamov');

INSERT INTO shipments (shipment_id, ship_ts, order_id, warehouse) VALUES ('ship-ch83360', '2019-03-31T18:13:39Z', 1, 'UPS');
INSERT INTO shipments (shipment_id, ship_ts, order_id, warehouse) VALUES ('ship-xf72808', '2019-03-31T02:04:13Z', 2, 'UPS');
INSERT INTO shipments (shipment_id, ship_ts, order_id, warehouse) VALUES ('ship-kr47454', '2019-03-31T20:47:09Z', 3, 'DHL');

SET 'auto.offset.reset' = 'earliest';

SELECT o.rowkey AS order_id,
       TIMESTAMPTOSTRING(o.rowtime, 'yyyy-MM-dd HH:mm:ss') AS order_ts,
       o.total_amount,
       o.customer_name,
       s.shipment_id,
       TIMESTAMPTOSTRING(s.rowtime, 'yyyy-MM-dd HH:mm:ss') AS shipment_ts,
       s.warehouse, (s.rowtime - o.rowtime) / 1000 / 60 AS ship_time
FROM orders o INNER JOIN shipments s
WITHIN 7 DAYS
ON o.rowkey = s.order_id
EMIT CHANGES
LIMIT 3;

CREATE STREAM shipped_orders AS
    SELECT o.rowkey AS order_id,
           TIMESTAMPTOSTRING(o.rowtime, 'yyyy-MM-dd HH:mm:ss') AS order_ts,
           o.total_amount,
           o.customer_name,
           s.shipment_id,
           TIMESTAMPTOSTRING(s.rowtime, 'yyyy-MM-dd HH:mm:ss') AS shipment_ts,
           s.warehouse, (s.rowtime - o.rowtime) / 1000 / 60 AS ship_time
    FROM orders o INNER JOIN shipments s
    WITHIN 7 DAYS
    ON o.rowkey = s.order_id;

PRINT 'SHIPPED_ORDERS' FROM BEGINNING LIMIT 3;
EOF


log "Invoke the tests"
docker exec ksqldb-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json | grep "Test passed!"
