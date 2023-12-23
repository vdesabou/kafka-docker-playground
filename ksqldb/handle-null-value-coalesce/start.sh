#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

# example with JSON
log "Create a topic named my-structure-json"
docker exec -i connect kafka-topics --create --bootstrap-server broker:9092 --topic my-structure-json --partitions 1
log "Produce records to my-structure-json"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --topic my-structure-json << EOF
{"desc":"Global"}
{"A":{"descA":"GlobalA"}}
{"A":{"B":{"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
{"A":{"B":{"C":{"id":"Cid"},"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
{"A":{"B":{"C":{"id":"Cid","descC":"DESCC"},"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
EOF

log "Create the ksqlDB stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM myStructureJSON(
  A STRUCT<B STRUCT<C STRUCT<id STRING, descC STRING>, descB STRING>, descA STRING>,
  desc STRING
) WITH (
  kafka_topic='my-structure-json',
  partitions=1,
  value_format='JSON'
);
EOF

# Wait for the stream to be initialized
sleep 10

log "Query this stream with COALESCE to handle the case where descC column is not set or NULL"
log "COALESCE returns the first parameter that is not NULL"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT COALESCE(A->B->C->descC, 'DEFAULT') descC
FROM myStructureJSON;
EOF

#Pre 0.26 there was a bug in de-referencing -> https://github.com/confluentinc/ksql/issues/7185
#The sql to select would be
# select case when A is null then 'DEFAULT'
#             when A->B is null then 'DEFAULT'
#             when A->B->C is null then 'DEFAULT'
#             else coalesce(A->B->C->descC,'DEFAULT')
#         end descC from structureJson emit changes;


# Expected output:
# +-----+
# |DESCC|
# +-----+
# |DEFAU|
# |LT   |
# |DEFAU|
# |LT   |
# |DEFAU|
# |LT   |
# |DEFAU|
# |LT   |
# |DESCC|
