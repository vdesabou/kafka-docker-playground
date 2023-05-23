#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.4.99"; then
    logerror "ERROR: This can only be run with version greater than 5.5"
    exit 111
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Register schema for customer"
curl -X POST http://localhost:8081/subjects/customer/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"fields\":[{\"name\":\"customer_id\",\"type\":\"int\"},{\"name\":\"customer_name\",\"type\":\"string\"},{\"name\":\"customer_email\",\"type\":\"string\"},{\"name\":\"customer_address\",\"type\":\"string\"}],\"name\":\"Customer\",\"namespace\":\"io.confluent.examples.avro\",\"type\":\"record\"}"

}'

log "Register schema for product"
curl -X POST http://localhost:8081/subjects/product/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"fields\":[{\"name\":\"product_id\",\"type\":\"int\"},{\"name\":\"product_name\",\"type\":\"string\"},{\"name\":\"product_price\",\"type\":\"double\"}],\"name\":\"Product\",\"namespace\":\"io.confluent.examples.avro\",\"type\":\"record\"}"
}'

log "Register schema for all-types"
curl -X POST http://localhost:8081/subjects/all-types-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "[\"io.confluent.examples.avro.Customer\",\"io.confluent.examples.avro.Product\"]",
    "references": [
      {
        "name": "io.confluent.examples.avro.Customer",
        "subject":  "customer",
        "version": 1
      },
      {
        "name": "io.confluent.examples.avro.Product",
        "subject":  "product",
        "version": 1
      }
    ]
}'

log "Get schema id for all-types"
id=$(curl http://localhost:8081/subjects/customer/versions/1/referencedby | tr -d '[' | tr -d ']')

log "Produce some Customer and Product data in topic all-types"
# property auto.register.schemas was added in 5.5.2, need to use auto.register for previous versions #1651
AUTO_REGISTER_PROPERTY="auto.register.schemas"
if ! version_gt $TAG_BASE "5.5.2"; then
    AUTO_REGISTER_PROPERTY="auto.register"
fi
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic all-types --property value.schema.id=$id --property $AUTO_REGISTER_PROPERTY=false --property use.latest.version=true << EOF
{ "io.confluent.examples.avro.Product": { "product_id": 1, "product_name" : "rice", "product_price" : 100.00 } }
{ "io.confluent.examples.avro.Customer": { "customer_id": 100, "customer_name": "acme", "customer_email": "acme@google.com", "customer_address": "1 Main St" } }
EOF

log "Check that data is there"
playground topic consume --topic all-types --expected-messages 2


