#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

log "Create the ksqlDB stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

CREATE STREAM ratings (title VARCHAR, release_year INT, rating DOUBLE, timestamp VARCHAR)
    WITH (kafka_topic='ratings',
          timestamp='timestamp',
          timestamp_format='yyyy-MM-dd HH:mm:ss',
          partitions=1,
          value_format='avro');
EOF

log "Insert records to the stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Die Hard', 1998, 8.2, '2019-07-09 01:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Die Hard', 1998, 4.5, '2019-07-09 05:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Die Hard', 1998, 5.1, '2019-07-09 07:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Tree of Life', 2011, 4.9, '2019-07-09 09:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Tree of Life', 2011, 5.6, '2019-07-09 08:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('A Walk in the Clouds', 1995, 3.6, '2019-07-09 12:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('A Walk in the Clouds', 1995, 6.0, '2019-07-09 15:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('A Walk in the Clouds', 1995, 4.6, '2019-07-09 22:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('The Big Lebowski', 1998, 9.9, '2019-07-09 05:00:00');
INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('The Big Lebowski', 1998, 4.2, '2019-07-09 02:00:00');

INSERT INTO ratings (title, release_year, rating, timestamp) VALUES ('Super Mario Bros.', 1993, 3.5, '2019-07-09 18:00:00');

EOF

# Wait for the stream to be initialized
sleep 5

log "Run a query to see how many ratings were given to each movie in tumbling, 6-hour intervals"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT title,
       COUNT(*) AS rating_count,
       WINDOWSTART AS window_start,
       WINDOWEND AS window_end
FROM ratings
WINDOW TUMBLING (SIZE 6 HOURS)
GROUP BY title
EMIT CHANGES
LIMIT 11;

EOF

# This should yield the following output:
# +--------------------+--------------------+--------------------+--------------------+
# |TITLE               |RATING_COUNT        |WINDOW_START        |WINDOW_END          |
# +--------------------+--------------------+--------------------+--------------------+
# |Die Hard            |1                   |1562630400000       |1562652000000       |
# |Die Hard            |2                   |1562630400000       |1562652000000       |
# |Die Hard            |1                   |1562652000000       |1562673600000       |
# |Tree of Life        |1                   |1562652000000       |1562673600000       |
# |Tree of Life        |2                   |1562652000000       |1562673600000       |
# |A Walk in the Clouds|1                   |1562673600000       |1562695200000       |
# |A Walk in the Clouds|2                   |1562673600000       |1562695200000       |
# |A Walk in the Clouds|1                   |1562695200000       |1562716800000       |
# |The Big Lebowski    |1                   |1562630400000       |1562652000000       |
# |The Big Lebowski    |2                   |1562630400000       |1562652000000       |
# |Super Mario Bros.   |1                   |1562695200000       |1562716800000       |
# Limit Reached
# Query terminated

log "We can create a table based on this window aggregation"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE rating_count
    WITH (kafka_topic='rating_count') AS
    SELECT title,
           COUNT(*) AS rating_count,
           WINDOWSTART AS window_start,
           WINDOWEND AS window_end
    FROM ratings
    WINDOW TUMBLING (SIZE 6 HOURS)
    GROUP BY title;

EOF

# Wait for the stream to be initialized
sleep 5
log "Running query which uses the TIMESTAMPTOSTRING function to convert the UNIX timestamps into something that we can read"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT title,
       rating_count,
       TIMESTAMPTOSTRING(window_start, 'yyy-MM-dd HH:mm:ss', 'UTC') as window_start,
       TIMESTAMPTOSTRING(window_end, 'yyy-MM-dd HH:mm:ss', 'UTC') as window_end
FROM rating_count
EMIT CHANGES
LIMIT 11;

EOF

# The output should look similar to:
# +--------------------+--------------------+--------------------+--------------------+
# |TITLE               |RATING_COUNT        |WINDOW_START        |WINDOW_END          |
# +--------------------+--------------------+--------------------+--------------------+
# |Die Hard            |1                   |2019-07-09 00:00:00 |2019-07-09 06:00:00 |
# |Die Hard            |2                   |2019-07-09 00:00:00 |2019-07-09 06:00:00 |
# |Die Hard            |1                   |2019-07-09 06:00:00 |2019-07-09 12:00:00 |
# |Tree of Life        |1                   |2019-07-09 06:00:00 |2019-07-09 12:00:00 |
# |Tree of Life        |2                   |2019-07-09 06:00:00 |2019-07-09 12:00:00 |
# |A Walk in the Clouds|1                   |2019-07-09 12:00:00 |2019-07-09 18:00:00 |
# |A Walk in the Clouds|2                   |2019-07-09 12:00:00 |2019-07-09 18:00:00 |
# |A Walk in the Clouds|1                   |2019-07-09 18:00:00 |2019-07-10 00:00:00 |
# |The Big Lebowski    |1                   |2019-07-09 00:00:00 |2019-07-09 06:00:00 |
# |The Big Lebowski    |2                   |2019-07-09 00:00:00 |2019-07-09 06:00:00 |
# |Super Mario Bros.   |1                   |2019-07-09 18:00:00 |2019-07-10 00:00:00 |
# Limit Reached
# Query terminated
