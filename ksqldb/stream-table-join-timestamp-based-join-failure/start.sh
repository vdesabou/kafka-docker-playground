#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

log "Create topics"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic orders --partitions 1 --config retention.ms=-1 --config retention.bytes=-1
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic customers --partitions 1 --config retention.ms=-1 --config retention.bytes=-1
log "Produce records to the stream"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic orders << EOF
{"id":101,"customer_id":1,"total":56.03,"order_date":1696340019}
{"id":102,"customer_id":2,"total":89.03,"order_date":1696340080}
{"id":103,"customer_id":3,"total":19.03,"order_date":1696346959}
EOF

log "Create the ksqlDB table and the Stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE customers (
  id INT PRIMARY KEY,
  first_name VARCHAR,
  last_name VARCHAR,
  created_at BIGINT
) WITH (
  kafka_topic='customers',
  value_format='json',
  timestamp = 'created_at'
);

INSERT INTO customers (id, first_name, last_name, created_at) VALUES (1, 'John','Doe', 1696346919);
INSERT INTO customers (id, first_name, last_name, created_at) VALUES (2, 'Jane','Doe', 1696346929);
INSERT INTO customers (id, first_name, last_name, created_at) VALUES (3, 'Michel','Polnaref', 1696346939);

CREATE STREAM orders (id INTEGER, customer_id INTEGER, total DOUBLE, order_date BIGINT) WITH (kafka_topic='orders', value_format='json', timestamp='order_date');

EOF

log "The rowtime of the record from my stream is earlier than the rowtime of the record in my table that I expect it to join with"

# Wait for the stream to be initialized
sleep 5

log "We join the STREAM and the TABLE"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT orders.id AS ID, total, first_name, last_name
   FROM orders
   LEFT JOIN customers ON orders.customer_id = customers.id
   EMIT CHANGES LIMIT 3;
EOF

# Expected output query
# +-----+-----+-----+-----+
# |ID   |TOTAL|FIRST|LAST_|
# |     |     |_NAME|NAME |
# +-----+-----+-----+-----+
# |101  |56.03|null |null |
# |102  |89.03|null |null |
# |103  |19.03|Miche|Polna|
# |     |     |l    |ref  |

log "The rowtime of order 103 is after the rowtime of table, so the join will be successful"

log "Produce more records to the stream with ROWTIME after the rowtime of table"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic orders << EOF
{"id":104,"customer_id":1,"total":18,"order_date":1696346959}
{"id":105,"customer_id":2,"total":45.56,"order_date":1696346969}
{"id":106,"customer_id":3,"total":78.96,"order_date":1696346979}
EOF

log "We can run again the stream-table join"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT orders.id AS ID, total, first_name, last_name
   FROM orders
   LEFT JOIN customers ON orders.customer_id = customers.id
   EMIT CHANGES LIMIT 6;
EOF

# Expected output
# +-----+-----+-----+-----+
# |ID   |TOTAL|FIRST|LAST_|
# |     |     |_NAME|NAME |
# +-----+-----+-----+-----+
# |101  |56.03|null |null |
# |102  |89.03|null |null |
# |103  |19.03|Miche|Polna|
# |     |     |l    |ref  |
# |104  |18.0 |John |Doe  |
# |105  |45.56|Jane |Doe  |
# |106  |78.96|Miche|Polna|
# |     |     |l    |ref  |

log "With stream-table join, your table messages must already exist (and must be timestamped) before the stream messages."
