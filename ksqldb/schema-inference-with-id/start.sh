#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

# has to remove the price field otherwise it fails because ksqlDB schema inference is not able to handle float32
# https://github.com/confluentinc/ksql/issues/9740
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" -X POST http://schema-registry:8081/subjects/orders-value/versions --data '{"schema":"{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"}]}"}'

log "Checking the schema existence in the schema registry"
docker exec -i connect curl -s GET http://schema-registry:8081/subjects/orders-value/versions/1

log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema.id=1 << EOF
{"id": 111, "product": "foo1", "quantity": 101}
{"id": 222, "product": "foo2", "quantity": 102}
EOF


log "Create the ksqlDB streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM orders
  WITH (
    KAFKA_TOPIC='orders',
    VALUE_FORMAT='AVRO',
    VALUE_SCHEMA_ID=1
  );

CREATE STREAM orders_new
WITH (
  KAFKA_TOPIC='orders_new',
  VALUE_FORMAT='AVRO',
  VALUE_SCHEMA_ID=1
) AS 
SELECT
  *
FROM orders;
EOF

log "Checking the orders_new topic has its own schema with the same schema ID as orders topic (ie. ID=1)"
docker exec -i connect curl -s GET http://schema-registry:8081/subjects/orders_new-value/versions/1

log "Verify we have received the data in orders_new topic"
playground topic consume --topic orders_new --min-expected-messages 2

log "Updating the schema"
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" -X POST http://schema-registry:8081/subjects/orders-value/versions --data '{"schema":"{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"},{\"name\":\"category\",\"type\":\"string\",\"default\":\"default_category\"}]}"}'

log "Checking the schema existence of the new version in the schema registry"
docker exec -i connect curl -s GET http://schema-registry:8081/subjects/orders-value/versions/2

log "Updating ksqlDB streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF

TERMINATE CSAS_ORDERS_NEW_1;

DROP STREAM orders_new;

CREATE OR REPLACE STREAM orders_new
WITH (
  KAFKA_TOPIC='orders_new',
  VALUE_FORMAT='AVRO',
  VALUE_SCHEMA_ID=2
) AS 
SELECT
  *
FROM orders;
EOF

# Wait for the stream to be initialized
sleep 5

log "Sending messages to topic orders using the new schema "
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema.id=2 << EOF
{"id": 333, "product": "foo3", "quantity": 103, "category": "sample"}
{"id": 444, "product": "foo4", "quantity": 104, "category": "sample"}
EOF

log "Checking the orders_new topic has an update schema(ie. ID=2)"
docker exec -i connect curl -s GET http://schema-registry:8081/subjects/orders_new-value/versions/2

log "Verify we have received the data in orders_new topic using both v1 and v2 schemas"
playground topic consume --topic orders_new --min-expected-messages 4
