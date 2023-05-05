#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

${DIR}/../../environment/plaintext/start.sh

docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" -X POST http://schema-registry:8081/subjects/orders-value/versions --data '{"schema":"{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"},{\"name\":\"price\",\"type\":\"float\"}]}"}'

log "Checking the schema existence in the schema registry"
docker exec -i connect curl -s GET http://schema-registry:8081/subjects/orders-value/versions/1


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema.id=1 << EOF
{"id": 111, "product": "foo1", "quantity": 101, "price": 51}
{"id": 222, "product": "foo2", "quantity": 102, "price": 52}
{"id": 333, "product": "foo3", "quantity": 103, "price": 53}
EOF


log "Create the ksqlDB tables and streams"
timeout 120 docker exec -i ksqldb-cli ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM orders
  WITH (
    KAFKA_TOPIC='orders',
    VALUE_FORMAT='AVRO',
    VALUE_SCHEMA_ID=1
  );

CREATE STREAM orders_filtered AS 
  SELECT
    product,
    price
  FROM orders
EOF