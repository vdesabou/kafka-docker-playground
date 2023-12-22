#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

playground start-environment --environment plaintext

log "Create the ksqlDB stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM ratings (old INT, id INT, rating DOUBLE)
    WITH (kafka_topic='ratings',
          partitions=2,
          value_format='avro');
EOF

log "Insert records to the stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
INSERT INTO ratings (old, id, rating) VALUES (1, 294, 8.2);
INSERT INTO ratings (old, id, rating) VALUES (2, 294, 8.5);
INSERT INTO ratings (old, id, rating) VALUES (3, 354, 9.9);
INSERT INTO ratings (old, id, rating) VALUES (4, 354, 9.7);
INSERT INTO ratings (old, id, rating) VALUES (5, 782, 7.8);
INSERT INTO ratings (old, id, rating) VALUES (6, 782, 7.7);
INSERT INTO ratings (old, id, rating) VALUES (7, 128, 8.7);
INSERT INTO ratings (old, id, rating) VALUES (8, 128, 8.4);
INSERT INTO ratings (old, id, rating) VALUES (9, 780, 2.1);
EOF

# Wait for the stream to be initialized
sleep 10

log "See the content of this topic"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
PRINT ratings FROM BEGINNING LIMIT 9;
EOF

log "Re-partition the topic with the movie ID"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM RATINGS_REKEYED
    WITH (KAFKA_TOPIC='ratings_keyed_by_id') AS
    SELECT *
    FROM RATINGS
    PARTITION BY ID;

DESCRIBE RATINGS_REKEYED;
EOF

# Wait for the stream to be initialized
sleep 10
log "Check the content of the rekey topic to ensure the key has been correctly set"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
PRINT ratings_keyed_by_id FROM BEGINNING LIMIT 9;
EOF

# This should yield the roughly the following output:
# ksql> Key format: KAFKA_INT
# Value format: AVRO
# rowtime: 2023/10/05 09:45:47.087 Z, key: 354, value: {"OLD": 3, "RATING": 9.9}, partition: 0
# rowtime: 2023/10/05 09:45:47.458 Z, key: 782, value: {"OLD": 5, "RATING": 7.8}, partition: 0
# rowtime: 2023/10/05 09:45:47.633 Z, key: 782, value: {"OLD": 6, "RATING": 7.7}, partition: 0
# rowtime: 2023/10/05 09:45:46.585 Z, key: 294, value: {"OLD": 1, "RATING": 8.2}, partition: 0
# rowtime: 2023/10/05 09:45:46.885 Z, key: 294, value: {"OLD": 2, "RATING": 8.5}, partition: 0
# rowtime: 2023/10/05 09:45:47.274 Z, key: 354, value: {"OLD": 4, "RATING": 9.7}, partition: 0
# rowtime: 2023/10/05 09:45:47.824 Z, key: 128, value: {"OLD": 7, "RATING": 8.7}, partition: 0
# rowtime: 2023/10/05 09:45:47.989 Z, key: 128, value: {"OLD": 8, "RATING": 8.4}, partition: 0
# rowtime: 2023/10/05 09:45:48.155 Z, key: 780, value: {"OLD": 9, "RATING": 2.1}, partition: 1
# Topic printing ceased
