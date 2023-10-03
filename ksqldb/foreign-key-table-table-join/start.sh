#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

log "Create the ksqlDB tables"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE orders (
  id INT PRIMARY KEY,
  user_id INT,
  value INT
) WITH (
  KAFKA_TOPIC = 'my-orders-topic',
  VALUE_FORMAT = 'JSON',
  PARTITIONS = 2
);

CREATE TABLE users (
  u_id INT PRIMARY KEY,
  name VARCHAR,
  last_name VARCHAR
) WITH (
  KAFKA_TOPIC = 'my-users-topic',
  VALUE_FORMAT = 'JSON',
  PARTITIONS = 3
);

CREATE TABLE orders_with_users AS
SELECT * FROM orders JOIN users ON user_id = u_id
EMIT CHANGES;

EOF

log "Insert the records to these two tables"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

INSERT INTO orders (id, user_id, value) VALUES (1, 1, 100);
INSERT INTO orders (id, user_id, value) VALUES (2, 2, 123);
INSERT INTO orders (id, user_id, value) VALUES (3, 2, 145);
INSERT INTO orders (id, user_id, value) VALUES (4, 3, 80);
INSERT INTO orders (id, user_id, value) VALUES (5, 3, 20);

INSERT INTO users (u_id, name, last_name) VALUES (1, 'John', 'Smith');
INSERT INTO users (u_id, name, last_name) VALUES (2, 'Jane', 'Birkin');
INSERT INTO users (u_id, name, last_name) VALUES (3, 'Serge', 'Gainsbourg');

EOF

# Wait for the stream to be initialized
sleep 5

log "Query the FK table-table joins"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM orders_with_users;
EOF
