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
docker exec -i connect kafka-console-producer --bootstrap-server broker:9092 --topic my-structure-json << EOF
{"field1":"value11","field2":[]}
{"field1":"value12","field2":null}
{"field1":"value13","field2":[{"field21":"value21","field22":"value22"}]}
EOF

log "Create the ksqlDB stream"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
CREATE STREAM myStructureJSON(rowkey string key, field1 string, field2 array<struct<field21 string, field22 string>>)
WITH (kafka_topic='my-structure-json', value_format='json');
EOF

# Wait for the stream to be initialized
sleep 10

log "Query this stream with EXPLODE + CASE to handle empty array or null value"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF
SET 'auto.offset.reset' = 'earliest';
SELECT
  rowkey,
  field1,
  EXPLODE(CASE when array_length(field2) > 0 then field2 else array[struct(field21 := 'null', field22 := 'null')] end) as field2
FROM myStructureJSON;

EOF

# Expected output:
# |ROWKE|FIELD|FIELD|
# |Y    |1    |2    |
# +-----+-----+-----+
# |null |value|{FIEL|
# |     |11   |D21=n|
# |     |     |ull, |
# |     |     |FIELD|
# |     |     |22=nu|
# |     |     |ll}  |
# |null |value|{FIEL|
# |     |12   |D21=n|
# |     |     |ull, |
# |     |     |FIELD|
# |     |     |22=nu|
# |     |     |ll}  |
# |null |value|{FIEL|
# |     |13   |D21=v|
# |     |     |alue2|
# |     |     |1, FI|
# |     |     |ELD22|
# |     |     |=valu|
# |     |     |e22} |
