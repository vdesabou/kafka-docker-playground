#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

# CASE 1 -> With an optional field
log "Register an Avro schema with an Optional field"
docker exec -i connect curl -s -H "Content-Type: application/vnd.schemaregistry.v1+json" -X POST http://schema-registry:8081/subjects/orders-value/versions --data '{"schema":"{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"product\",\"type\":\"string\"},{\"name\":\"quantity\",\"type\":\"int\"},{\"name\":\"description\",\"type\":[\"null\",\"string\"],\"default\":null}]}"}'

log "Checking the schema existence in the schema registry"
docker exec -i connect curl -s GET http://schema-registry:8081/subjects/orders-value/versions/1

log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema.id=1 << EOF
{"id": 111, "product": "foo1", "quantity": 101, "description": {"string":"my-first-command"}}
{"id": 222, "product": "foo2", "quantity": 102, "description": null}
EOF

log "Consuming records from topic orders"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 \
    --topic orders  --from-beginning \
    --property schema.registry.url=http://schema-registry:8081 --property print.schema.ids=true  --property schema.id.separator=: \
    --max-messages 2


# CASE 2 -> With Mutiple Event Types in the same Topic
log "Register the Avro schema for Customer"
playground schema register --subject customer << 'EOF'
{
  "fields": [
    {
      "name": "customer_id",
      "type": "int"
    },
    {
      "name": "customer_name",
      "type": "string"
    },
    {
      "name": "customer_email",
      "type": "string"
    },
    {
      "name": "customer_address",
      "type": "string"
    }
  ],
  "name": "Customer",
  "namespace": "io.confluent.examples.avro",
  "type": "record"
}
EOF

log "Register the Avro schema for Product"
playground schema register --subject product << 'EOF'
{
  "fields": [
    {
      "name": "product_id",
      "type": "int"
    },
    {
      "name": "product_name",
      "type": "string"
    },
    {
      "name": "product_price",
      "type": "double"
    }
  ],
  "name": "Product",
  "namespace": "io.confluent.examples.avro",
  "type": "record"
}
EOF

log "Register the Avro schema for avro-alltypes-value"
playground schema register --subject avro-alltypes-value << 'EOF'
{
  "schema":"[\"io.confluent.examples.avro.Customer\",\"io.confluent.examples.avro.Product\"]",
  "schemaType":"AVRO",
  "references":[
    {
      "name":"io.confluent.examples.avro.Customer",
      "subject":"customer",
      "version":1
    },
    {
      "name":"io.confluent.examples.avro.Product",
      "subject":"product",
      "version":1
    }
  ]
}
EOF

log "Produce records to avro-alltypes topic"
playground topic produce --topic avro-alltypes --forced-value '{ "io.confluent.examples.avro.Product": { "product_id": 1, "product_name" : "rice", "product_price" : 100.00 } }' --value-schema-id 3 << 'EOF'
{
  "fields": [
    {
      "name": "product_id",
      "type": "int"
    },
    {
      "name": "product_name",
      "type": "string"
    },
    {
      "name": "product_price",
      "type": "double"
    }
  ],
  "name": "Product",
  "namespace": "io.confluent.examples.avro",
  "type": "record"
}
EOF

playground topic produce --topic avro-alltypes --forced-value '{ "io.confluent.examples.avro.Customer": { "customer_id": 100, "customer_name": "acme", "customer_email": "acme@google.com", "customer_address": "1 Main St" } }' --value-schema-id 3 << 'EOF'
{
  "fields": [
    {
      "name": "customer_id",
      "type": "int"
    },
    {
      "name": "customer_name",
      "type": "string"
    },
    {
      "name": "customer_email",
      "type": "string"
    },
    {
      "name": "customer_address",
      "type": "string"
    }
  ],
  "name": "Customer",
  "namespace": "io.confluent.examples.avro",
  "type": "record"
}
EOF

log "Consuming records from this topic"
playground topic consume --topic avro-alltypes



##
## JSON SCHEMA EXAMPLE

log "Register the Json Schema schema for address-json"
playground schema register --subject address-json << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "http://example.com/address.schema.json",
  "title": "Address",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "street": {
      "type": "string"
    },
    "street2": {
      "type": "string"
    },
    "city": {
      "type": "string"
    },
    "state": {
      "type": "string"
    },
    "postalCode": {
      "type": "string"
    },
    "countryCode": {
      "type": "string"
    }
  },
  "required": [
    "street",
    "city",
    "postalCode",
    "countryCode"
  ]
}
EOF

log "Register the Json Schema schema for json-schema-alltypes-value"
playground schema register --subject json-schema-alltypes-value << 'EOF'
{
  "schemaType": "JSON",
  "schema": "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"$id\":\"http://example.com/customer.schema.json\",\"title\":\"Customer\",\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"firstName\":{\"type\":\"string\"},\"lastName\":{\"type\":\"string\"},\"address\":{\"$ref\":\"address.schema.json\"}},\"required\":[\"firstName\",\"lastName\",\"address\"]}",
  "references": [
    {
      "name": "address.schema.json",
      "subject": "address-json",
      "version": 1
    }
  ]
}
EOF

log "Produce records to json-schema-alltypes topic"
playground topic produce --topic json-schema-alltypes --forced-value '{"firstName":"dolor","lastName":"tempor occaecat in","address":{"street":"id","street2":"anim esse commodo sint","city":"aute aliqua in tempor","postalCode":"in consectetur laborum","countryCode":"deserunt ex"}}' --value-schema-id 5 << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "http://example.com/address.schema.json",
  "title": "Address",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "street": {
      "type": "string"
    },
    "street2": {
      "type": "string"
    },
    "city": {
      "type": "string"
    },
    "state": {
      "type": "string"
    },
    "postalCode": {
      "type": "string"
    },
    "countryCode": {
      "type": "string"
    }
  },
  "required": [
    "street",
    "city",
    "postalCode",
    "countryCode"
  ]
}
EOF


log "Consuming records from this topic"
playground topic consume --topic json-schema-alltypes


###
# PROTOBUF EXAMPLE
#

log "Register the Protobuf schema for Address"
playground schema register --subject address-proto << 'EOF'
syntax = "proto3";

package com.example;

message Address {
  string street = 1;
  optional string street2 = 2;
  string city = 3;
  optional string state = 4;
  string postalCode = 5;
  string countryCode = 6;
}
EOF


log "Register the Protobuf schema for protobuf-alltypes-value"
playground schema register --subject protobuf-alltypes-value << 'EOF'
{
  "references": [
    {
      "name": "com/example/address.proto",
      "subject": "address-proto",
      "version": 1
    }
  ],
  "schema": "syntax = \"proto3\";\n\npackage com.example;\n\nimport \"com/example/address.proto\";\n\nmessage Customer {\nstring firstName = 1;\nstring lastName = 2;\ncom.example.Address address = 3;\n}",
  "schemaType": "PROTOBUF"
}
EOF

log "Produce records to protobuf-alltypes topic"
playground topic produce --topic protobuf-alltypes --forced-value '{"firstName":"Gupdqph.","lastName":"Ovck aobggjqdzn.","address":{"street":"Pchhblish rnsvtvwg ozjizdo.","street2":"Oyxp ybbtddn.","city":"Spqkjlihb qqsmiwufn tewcgudxt.","state":"Fwbwky yqvzcw viio fqsehza.","postalCode":"Wooxyyx slnr wmbf.","countryCode":"Ycfpnnh oknlsgup dczjgouyo edevdbuong."}}' --value-schema-id 7 << 'EOF'
syntax = "proto3";

package com.example;

import "com/example/address.proto";

message Customer {
  string firstName = 1;
  string lastName = 2;
  com.example.Address address = 3;
}
EOF


log "Consuming records from this topic"
playground topic consume --topic protobuf-alltypes