#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

# has to remove the price field otherwise it fails because ksqlDB schema inference is not able to handle float32
# https://github.com/confluentinc/ksql/issues/9740
playground schema register --subject orders-value << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"}]}
EOF

log "Checking the schema existence in the schema registry"
playground schema get --subject orders-value --version 1

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 --forced-value '{"id": 111, "product": "foo1", "quantity": 101}' << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"}]}
EOF
playground topic produce -t orders --nb-messages 1 --forced-value '{"id": 222, "product": "foo2", "quantity": 102}' << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"}]}
EOF

playground ksqldb wait

log "Create the ksqlDB streams"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM orders
  WITH (
    KAFKA_TOPIC='orders',
    VALUE_FORMAT='AVRO'
  );

SELECT * FROM orders;

CREATE STREAM orders_new
WITH (
  KAFKA_TOPIC='orders_new',
  VALUE_FORMAT='AVRO') AS
SELECT
  *
FROM orders;

EOF

log "Updating the schema"
playground schema register --subject orders-value << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"category","type":"string","default":"default_category"}]}
EOF

log "Checking the schema existence of the new version in the schema registry"
playground schema get --subject orders-value --version 2

log "Sending messages to topic orders using the new schema "
playground topic produce -t orders --nb-messages 1 --forced-value '{"id": 333, "product": "foo3", "quantity": 103, "category": "sample"}' << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"category","type":"string","default":"default_category"}]}
EOF
playground topic produce -t orders --nb-messages 1 --forced-value '{"id": 444, "product": "foo4", "quantity": 104, "category": "sample"}' << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product","type":"string"},{"name":"quantity","type":"int"},{"name":"category","type":"string","default":"default_category"}]}
EOF

playground ksqldb wait

log "Reading from ksqlDB stream"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

SELECT * FROM orders;
SELECT * FROM orders_new;
EOF

log "As for changes to your schema, it will be necessary to create a new ksql stream to handle such changes."
playground ksqldb sql << EOF
SET 'auto.offset.reset' = 'earliest';

TERMINATE CSAS_ORDERS_NEW_1;
DROP STREAM orders_new;

CREATE OR REPLACE STREAM orders
  WITH (
    KAFKA_TOPIC='orders',
    VALUE_FORMAT='AVRO'
  );

CREATE OR REPLACE STREAM orders_new
WITH (
  KAFKA_TOPIC='orders_new',
  VALUE_FORMAT='AVRO') AS
SELECT
  *
FROM orders;

SELECT * FROM orders;
SELECT * FROM orders_new;

EOF
