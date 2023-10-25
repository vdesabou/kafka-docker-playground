#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

log "Create the topic rhsTopic and lhsTopic"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic rhsTopic --partitions 1
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic lhsTopic --partitions 1

log "Create the Streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

CREATE STREAM astr(id STRING KEY, desc STRING)
  WITH(kafka_topic='rhsTopic', value_format='JSON');

CREATE STREAM lhsstr(id STRING KEY, desc STRING, field1 STRING)
  WITH(kafka_topic='lhsTopic', value_format='JSON');

EOF

log "Producing records to the Stream rhsTopic"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic rhsTopic --property parse.key=true --property key.separator=? << EOF
1?{"desc":"ABC"}
2?{"desc":"ABC"}
3?{"desc":"DEF"}
1?{"desc":"ABC"}
2?{"desc":"ABC"}
3?{"desc":"DEF"}
EOF
log "Producing records to the Stream lhsTopic"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic lhsTopic --property parse.key=true --property key.separator=? << EOF
a?{"field1":"value1","desc":"ABC"}
b?{"field1":"value1","desc":"DEF"}
EOF

# Wait for the stream to be initialized
sleep 5

log "Reading the content of both Streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM ASTR EMIT CHANGES LIMIT 6;
SELECT * FROM LHSSTR EMIT CHANGES LIMIT 2;
EOF

log "Creating a table based on Stream ASTR using COLLECT_LIST()"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE RHSTBL as SELECT desc, COLLECT_LIST(id) ids FROM ASTR GROUP BY DESC EMIT CHANGES;
EOF
sleep 5

log "Create a Stream named JOINSTR: a JOIN between the Stream and the Table"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM RHSTBL;

CREATE STREAM JOINSTR AS SELECT * FROM LHSSTR L INNER JOIN RHSTBL R ON L.DESC = R.DESC EMIT CHANGES;

EOF
# expected output of SELECT * FROM RHSTBL:
# +-------------------------------------------------------------------------------------------------------+-------------------------------------------------------------------------------------------------------+
# |DESC                                                                                                   |IDS                                                                                                    |
# +-------------------------------------------------------------------------------------------------------+-------------------------------------------------------------------------------------------------------+
# |ABC                                                                                                    |[1, 2, 1, 2]                                                                                           |
# |DEF                                                                                                    |[3, 3]                                                                                                 |

sleep 5

log "The join emit will have an array for RHS fields which you can then explode"
log "Query the stream JOINSTR with EXPLODE()"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT EXPLODE(R_IDS) R_ID, * FROM JOINSTR EMIT CHANGES;

EOF
# expected output:
# +---------------------------------+---------------------------------+---------------------------------+---------------------------------+---------------------------------+---------------------------------+
# |R_ID                             |L_DESC                           |L_ID                             |L_FIELD1                         |R_DESC                           |R_IDS                            |
# +---------------------------------+---------------------------------+---------------------------------+---------------------------------+---------------------------------+---------------------------------+
# |1                                |ABC                              |a                                |value1                           |ABC                              |[1, 2, 1, 2]                     |
# |2                                |ABC                              |a                                |value1                           |ABC                              |[1, 2, 1, 2]                     |
# |1                                |ABC                              |a                                |value1                           |ABC                              |[1, 2, 1, 2]                     |
# |2                                |ABC                              |a                                |value1                           |ABC                              |[1, 2, 1, 2]                     |
# |3                                |DEF                              |b                                |value1                           |DEF                              |[3, 3]                           |
# |3                                |DEF                              |b                                |value1                           |DEF                              |[3, 3]                           |
