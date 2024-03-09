#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

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


# simpler
playground topic produce --topic avro-alltypes2 << 'EOF'
[ 
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
  },
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
]
EOF
log "Consuming records from this topic"
playground topic consume --topic avro-alltypes2