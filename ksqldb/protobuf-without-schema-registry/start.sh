#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Send message in raw Protobuf, without Schema Registry"
playground container exec -c proto_producer --command "python producer.py"

log "Create the ksqlDB stream"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM persons (key INT KEY, name STRING, id INT, email STRING, phones ARRAY<STRUCT<number STRING, type INT>>) with (kafka_topic='persons', partitions=1, value_format='PROTOBUF_NOSR');

EOF

playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

SELECT * FROM PERSONS LIMIT 1;

EOF
# expected OUTPUT
# +-----+-----+-----+-----+-----+
# |KEY  |NAME |ID   |EMAIL|PHONE|
# |     |     |     |     |S    |
# +-----+-----+-----+-----+-----+
# |82537|John |1234 |jdoe@|[{NUM|
# |3492 |Doe  |     |examp|BER=5|
# |     |     |     |le.co|55-43|
# |     |     |     |m    |21, T|
# |     |     |     |     |YPE=2|
# |     |     |     |     |}]   |

log "Create a new stream to convert my stream to Protobuf"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

CREATE STREAM persons_protobuf_sr
  WITH (kafka_topic='persons_with_sr', partitions=1, value_format='protobuf')
  AS SELECT * FROM persons;
EOF

playground ksqldb wait
log "Read from the new stream"
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

DESCRIBE persons_protobuf_sr extended;

PRINT persons_with_sr FROM BEGINNING LIMIT 1;

EOF
# Expected OUTPUT
# ksql> ksql> Key format: JSON or KAFKA_INT or KAFKA_STRING
# Value format: PROTOBUF
# rowtime: 2023/10/19 14:44:13.224 Z, key: 1234, value: NAME: "John Doe" ID: 1234 EMAIL: "jdoe@example.com" PHONES { NUMBER: "555-4321" TYPE: 2 }, partition: 0
