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
playground topic create --topic my-structure-json --nb-partitions 1
log "Produce records to my-structure-json"
playground topic produce -t my-structure-json --nb-messages 5 << 'EOF'
{"desc":"Global"}
{"A":{"descA":"GlobalA"}}
{"A":{"B":{"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
{"A":{"B":{"C":{"id":"Cid"},"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
{"A":{"B":{"C":{"id":"Cid","descC":"DESCC"},"descB":"GlobalB"},"descA":"GlobalA"},"desc":"Global"}
EOF

log "Create the ksqlDB stream"
playground ksqldb sql << EOF
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

playground ksqldb wait

log "Query this stream with COALESCE to handle the case where descC column is not set or NULL"
log "COALESCE returns the first parameter that is not NULL"
playground ksqldb sql << EOF
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
