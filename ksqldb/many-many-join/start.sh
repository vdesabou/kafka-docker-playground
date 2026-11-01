#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Create the topic rhsTopic and lhsTopic"
playground topic create --topic rhsTopic --nb-partitions 1
playground topic create --topic lhsTopic --nb-partitions 1

log "Create the Streams"
playground ksqldb sql << EOF

CREATE STREAM astr(id STRING KEY, desc STRING)
  WITH(kafka_topic='rhsTopic', value_format='JSON');

CREATE STREAM lhsstr(id STRING KEY, desc STRING, field1 STRING)
  WITH(kafka_topic='lhsTopic', value_format='JSON');

EOF

log "Producing records to the Stream rhsTopic"
# a raw key with a number is incremented for each record: keys 1, 2 and 3, sent twice
for i in 1 2
do
playground topic produce -t rhsTopic --nb-messages 3 --key '1' << 'EOF'
{"desc":"ABC"}
{"desc":"ABC"}
{"desc":"DEF"}
EOF
done
log "Producing records to the Stream lhsTopic"
playground topic produce -t lhsTopic --nb-messages 1 --key 'a' << 'EOF'
{"field1":"value1","desc":"ABC"}
EOF
playground topic produce -t lhsTopic --nb-messages 1 --key 'b' << 'EOF'
{"field1":"value1","desc":"DEF"}
EOF

playground ksqldb wait

log "Reading the content of both Streams"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM ASTR EMIT CHANGES LIMIT 6;
SELECT * FROM LHSSTR EMIT CHANGES LIMIT 2;
EOF

log "Creating a table based on Stream ASTR using COLLECT_LIST()"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE TABLE RHSTBL as SELECT desc, COLLECT_LIST(id) ids FROM ASTR GROUP BY DESC EMIT CHANGES;
EOF
playground ksqldb wait

log "Create a Stream named JOINSTR: a JOIN between the Stream and the Table"
playground ksqldb sql << EOF
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

playground ksqldb wait

log "The join emit will have an array for RHS fields which you can then explode"
log "Query the stream JOINSTR with EXPLODE()"
# a push query with EXPLODE and a LIMIT fails on ksqlDB 8.4 ("Can't find any functions with the name 'EXPLODE'"):
# stop it after 15 seconds instead
playground ksqldb sql --query-timeout 15 << EOF
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
