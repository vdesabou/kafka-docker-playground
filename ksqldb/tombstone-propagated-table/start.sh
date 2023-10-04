#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

log "Example with the HAVING clause"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM TEMP_CITY_FOO(CITY VARCHAR, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.foo',VALUE_FORMAT = 'AVRO', PARTITIONS = 1);

INSERT INTO TEMP_CITY_FOO VALUES('PUN','34');
INSERT INTO TEMP_CITY_FOO VALUES('MUM','38');
INSERT INTO TEMP_CITY_FOO VALUES('KOL','39');
INSERT INTO TEMP_CITY_FOO VALUES('MUM','41');
INSERT INTO TEMP_CITY_FOO VALUES('PUN','28');

CREATE TABLE TEMP_CITY_FOO_LATEST WITH(KAFKA_TOPIC = 'temp.city.latest.foo',VALUE_FORMAT = 'AVRO', PARTITIONS = 1)
AS SELECT CITY,LATEST_BY_OFFSET(TEMP) AS TEMP FROM TEMP_CITY_FOO GROUP BY CITY HAVING latest_by_offset(TEMP, false) IS NOT NULL EMIT CHANGES;

EOF

# Wait for the stream to be initialized
sleep 5

timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT * FROM TEMP_CITY_FOO_LATEST WHERE CITY = 'KOL';
EOF

# Expected output:
# >
# +-----+-----+
# |CITY |TEMP |
# +---+-------+
# |KOL |39 |

log "You can add a logical tombstone to your topic"
log "Because of the HAVING latest_by_offset(TEMP, false) IS NOT NULL clause, it will remove the value for the key `KOL`"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
INSERT INTO TEMP_CITY_FOO VALUES('KOL',null);
EOF

# Wait for the stream to be initialized
sleep 5
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT * FROM TEMP_CITY_FOO_LATEST WHERE CITY = 'KOL';
print 'temp.city.latest.foo' from beginning LIMIT 4;
EOF

# Expected output:
# ksql> print `temp.city.latest.foo` from beginning;
# Key format: KAFKA_STRING
# Value format: AVRO or KAFKA_STRING
# rowtime: 2023/04/04 14:06:12.915 Z, key: KOL, value: {"TEMP": "39"}, partition: 0
# rowtime: 2023/04/04 14:06:12.940 Z, key: MUM, value: {"TEMP": "41"}, partition: 0
# rowtime: 2023/04/04 14:06:12.966 Z, key: PUN, value: {"TEMP": "28"}, partition: 0
# rowtime: 2023/04/04 14:08:39.769 Z, key: KOL, value: <null>, partition: 0



log "Example with the source table"
log "Create the Stream and the source table"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM TEMP_CITY_BAR(CITY VARCHAR, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.bar',VALUE_FORMAT = 'AVRO', PARTITIONS = 1);

INSERT INTO TEMP_CITY_BAR VALUES('PUN','34');
INSERT INTO TEMP_CITY_BAR VALUES('MUM','38');
INSERT INTO TEMP_CITY_BAR VALUES('KOL','39');
INSERT INTO TEMP_CITY_BAR VALUES('MUM','41');
INSERT INTO TEMP_CITY_BAR VALUES('PUN','28');

CREATE TABLE TEMP_CITY_BAR_LATEST WITH(KAFKA_TOPIC = 'temp.city.bar.latest',VALUE_FORMAT = 'AVRO', PARTITIONS = 1)
AS SELECT CITY,LATEST_BY_OFFSET(TEMP) AS TEMP FROM TEMP_CITY_BAR GROUP BY CITY EMIT CHANGES;

INSERT INTO TEMP_CITY_BAR VALUES('KOL','42');
EOF

# Wait for the stream to be initialized
sleep 10
log "Insert the tombstone"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM TEMP_CITY_BAR_TOMBSTONE(CITY VARCHAR KEY, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.bar.latest',VALUE_FORMAT = 'KAFKA');

INSERT INTO TEMP_CITY_BAR_TOMBSTONE VALUES('KOL',CAST(NULL AS VARCHAR));
EOF

sleep 10
log "We create the source table based on the topic temp.city.bar.latest"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE SOURCE TABLE TEMP_CITY_BAR_LATEST_SOURCE(CITY VARCHAR PRIMARY KEY, TEMP VARCHAR) WITH(KAFKA_TOPIC = 'temp.city.bar.latest',VALUE_FORMAT = 'AVRO', PARTITIONS = 1);

EOF

# Wait for the stream to be initialized
sleep 20
log "Checking the content of the table TEMP_CITY_BAR_LATEST_SOURCE"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * from TEMP_CITY_BAR_LATEST_SOURCE WHERE CITY = 'KOL';

EOF

# Expected output
# ksql> SELECT * from TEMP_CITY_BAR_LATEST_SOURCE WHERE CITY = 'KOL';
# +-----+------+
# |CITY |TEMP |
# +----+-------+
# Query terminated
