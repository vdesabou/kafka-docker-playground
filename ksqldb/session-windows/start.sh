#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

log "Create the ksqlDB stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

CREATE STREAM clicks (ip VARCHAR, url VARCHAR, timestamp VARCHAR)
WITH (KAFKA_TOPIC='clicks',
      TIMESTAMP='timestamp',
      TIMESTAMP_FORMAT='yyyy-MM-dd''T''HH:mm:ssX',
      PARTITIONS=1,
      VALUE_FORMAT='Avro');
EOF

log "Insert records to the stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
INSERT INTO clicks (ip, timestamp, url) VALUES ('51.56.119.117',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP()),'yyyy-MM-dd''T''HH:mm:ssX'),'/etiam/justo/etiam/pretium/iaculis.xml');
INSERT INTO clicks (ip, timestamp, url) VALUES ('51.56.119.117',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (60 * 1000)),'yyyy-MM-dd''T''HH:mm:ssX'),'/nullam/orci/pede/venenatis.json');
INSERT INTO clicks (ip, timestamp, url) VALUES ('53.170.33.192',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (91 * 1000)),'yyyy-MM-dd''T''HH:mm:ssX'),'/mauris/morbi/non.jpg');
INSERT INTO clicks (ip, timestamp, url) VALUES ('51.56.119.117',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (96 * 1000)),'yyyy-MM-dd''T''HH:mm:ssX'),'/convallis/nunc/proin.jsp');
INSERT INTO clicks (ip, timestamp, url) VALUES ('53.170.33.192',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (2 * 60 * 1000)),'yyyy-MM-dd''T''HH:mm:ssX'),'/vestibulum/vestibulum/ante/ipsum/primis/in.json');
INSERT INTO clicks (ip, timestamp, url) VALUES ('51.56.119.117',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (63 * 60 * 1000) + 21),'yyyy-MM-dd''T''HH:mm:ssX'),'/vehicula/consequat/morbi/a/ipsum/integer/a.jpg');
INSERT INTO clicks (ip, timestamp, url) VALUES ('51.56.119.117',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (63 * 60 * 1000) + 50),'yyyy-MM-dd''T''HH:mm:ssX'),'/pede/venenatis.jsp');
INSERT INTO clicks (ip, timestamp, url) VALUES ('53.170.33.192',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (100 * 60 * 1000)),'yyyy-MM-dd''T''HH:mm:ssX'),'/nec/euismod/scelerisque/quam.xml');
INSERT INTO clicks (ip, timestamp, url) VALUES ('53.170.33.192',FORMAT_TIMESTAMP(FROM_UNIXTIME(UNIX_TIMESTAMP() + (100 * 60 * 1000) + 9),'yyyy-MM-dd''T''HH:mm:ssX'),'/ligula/nec/sem/duis.jsp');

EOF

# Wait for the stream to be initialized
sleep 5

log "Run a query to see how many ratings were given to each movie in tumbling, 6-hour intervals"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT
  FORMAT_TIMESTAMP(FROM_UNIXTIME(ROWTIME),'yyyy-MM-dd HH:mm:ss', 'UTC') AS ROWTIME_STR,
  TIMESTAMP
FROM CLICKS
EMIT CHANGES LIMIT 5;

EOF

# This should yield the following output:
# +--------------------+--------------------+
# |ROWTIME_STR         |TIMESTAMP           |
# +--------------------+--------------------+
# |2019-07-18 10:00:00 |2019-07-18T10:00:00Z|
# |2019-07-18 10:01:00 |2019-07-18T10:01:00Z|
# |2019-07-18 10:01:31 |2019-07-18T10:01:31Z|
# |2019-07-18 10:01:36 |2019-07-18T10:01:36Z|
# |2019-07-18 10:02:00 |2019-07-18T10:02:00Z|
# Limit Reached
# Query terminated

log "We can create a table based on this session window aggregation"
log "Configure ksqlDB to buffer the aggregates as it builds them. This makes the query feel like it responds more slowly, but it means that you get just one row per window"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SET 'ksql.streams.cache.max.bytes.buffering'='2000000';


SELECT IP,
       FORMAT_TIMESTAMP(FROM_UNIXTIME(WINDOWSTART),'yyyy-MM-dd HH:mm:ss', 'UTC') AS SESSION_START_TS,
       FORMAT_TIMESTAMP(FROM_UNIXTIME(WINDOWEND),'yyyy-MM-dd HH:mm:ss', 'UTC')   AS SESSION_END_TS,
       COUNT(*)                                                    AS CLICK_COUNT,
       WINDOWEND - WINDOWSTART                                     AS SESSION_LENGTH_MS
  FROM CLICKS
       WINDOW SESSION (5 MINUTES)
GROUP BY IP
EMIT CHANGES LIMIT 4;

EOF

# This should yield the following output:
# +--------------------+--------------------+--------------------+--------------------+--------------------+
# |IP                  |SESSION_START_TS    |SESSION_END_TS      |CLICK_COUNT         |SESSION_LENGTH_MS   |
# +--------------------+--------------------+--------------------+--------------------+--------------------+
# |51.56.119.117       |2019-07-18 10:00:00 |2019-07-18 10:01:36 |3                   |96000               |
# |53.170.33.192       |2019-07-18 10:01:31 |2019-07-18 10:02:00 |2                   |29000               |
# |51.56.119.117       |2019-07-18 11:03:21 |2019-07-18 11:03:50 |2                   |29000               |
# |53.170.33.192       |2019-07-18 11:40:00 |2019-07-18 11:40:09 |2                   |9000                |
# Limit Reached
# Query terminated

log "When ksqlDB builds aggregates, it emits the values as new messages are processed, meaning that you may see intermediate results on the screen too. When ksql.streams.cache.max.bytes.buffering was set above, this suppressed these"
log "If you change the value to zero and re-run the above query you’ll see the intermediate emissions too:"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SET 'ksql.streams.cache.max.bytes.buffering'='0';
SELECT IP,
       FORMAT_TIMESTAMP(FROM_UNIXTIME(WINDOWSTART),'yyyy-MM-dd HH:mm:ss', 'UTC') AS SESSION_START_TS,
       FORMAT_TIMESTAMP(FROM_UNIXTIME(WINDOWEND),'yyyy-MM-dd HH:mm:ss', 'UTC')   AS SESSION_END_TS,
       COUNT(*)                                                    AS CLICK_COUNT,
       WINDOWEND - WINDOWSTART                                     AS SESSION_LENGTH_MS
  FROM CLICKS
       WINDOW SESSION (5 MINUTES)
GROUP BY IP
EMIT CHANGES
LIMIT 9;

EOF

# This time you’ll see each aggregate update and be re-emitted as new messages are processed:
# +--------------------+--------------------+--------------------+--------------------+--------------------+
# |IP                  |SESSION_START_TS    |SESSION_END_TS      |CLICK_COUNT         |SESSION_LENGTH_MS   |
# +--------------------+--------------------+--------------------+--------------------+--------------------+
# |51.56.119.117       |2019-07-18 10:00:00 |2019-07-18 10:00:00 |1                   |0                   |
# |51.56.119.117       |2019-07-18 10:00:00 |2019-07-18 10:01:00 |2                   |60000               |
# |53.170.33.192       |2019-07-18 10:01:31 |2019-07-18 10:01:31 |1                   |0                   |
# |51.56.119.117       |2019-07-18 10:00:00 |2019-07-18 10:01:36 |3                   |96000               |
# |53.170.33.192       |2019-07-18 10:01:31 |2019-07-18 10:02:00 |2                   |29000               |
# |51.56.119.117       |2019-07-18 11:03:21 |2019-07-18 11:03:21 |1                   |0                   |
# |51.56.119.117       |2019-07-18 11:03:21 |2019-07-18 11:03:50 |2                   |29000               |
# |53.170.33.192       |2019-07-18 11:40:00 |2019-07-18 11:40:00 |1                   |0                   |
# |53.170.33.192       |2019-07-18 11:40:00 |2019-07-18 11:40:09 |2                   |9000                |
# Limit Reached
# Query terminated

log "Create a table based on this aggregation"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE TABLE IP_SESSIONS AS
SELECT IP,
       FORMAT_TIMESTAMP(FROM_UNIXTIME(WINDOWSTART),'yyyy-MM-dd HH:mm:ss', 'UTC') AS SESSION_START_TS,
       FORMAT_TIMESTAMP(FROM_UNIXTIME(WINDOWEND),'yyyy-MM-dd HH:mm:ss', 'UTC')   AS SESSION_END_TS,
       COUNT(*) AS CLICK_COUNT,
       WINDOWEND - WINDOWSTART AS SESSION_LENGTH_MS
  FROM CLICKS
       WINDOW SESSION (5 MINUTES)
GROUP BY IP;
EOF

# Wait for the stream to be initialized
sleep 10

log "Print the topic"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
PRINT IP_SESSIONS FROM BEGINNING LIMIT 5;
EOF

# Notice the key for each message. ksqlDB has combined the grouping key (IP address) with its window boundaries. It should look something like this:
# ksql> Key format: SESSION(KAFKA_STRING)
# Value format: AVRO
# rowtime: 2023/10/04 13:42:10.000 Z, key: [51.56.119.117@1696426930000/1696426930000], value: {"SESSION_START_TS": "2023-10-04 13:42:10", "SESSION_END_TS": "2023-10-04 13:42:10", "CLICK_COUNT": 1, "SESSION_LENGTH_MS": 0}, partition: 0
# rowtime: 2023/10/04 13:42:10.000 Z, key: [51.56.119.117@1696426930000/1696426930000], value: <null>, partition: 0
# rowtime: 2023/10/04 13:43:10.000 Z, key: [51.56.119.117@1696426930000/1696426990000], value: {"SESSION_START_TS": "2023-10-04 13:42:10", "SESSION_END_TS": "2023-10-04 13:43:10", "CLICK_COUNT": 2, "SESSION_LENGTH_MS": 60000}, partition: 0
# rowtime: 2023/10/04 13:43:42.000 Z, key: [53.170.33.192@1696427022000/1696427022000], value: {"SESSION_START_TS": "2023-10-04 13:43:42", "SESSION_END_TS": "2023-10-04 13:43:42", "CLICK_COUNT": 1, "SESSION_LENGTH_MS": 0}, partition: 0
# rowtime: 2023/10/04 13:43:10.000 Z, key: [51.56.119.117@1696426930000/1696426990000], value: <null>, partition: 0
# Topic printing ceased
