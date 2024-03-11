#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

##
## JSON SCHEMA EXAMPLE

log "Register the Json Schema schema for address-json"
playground schema register --subject address-json << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "address.schema.json",
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
  "schema": "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"$id\":\"customer.schema.json\",\"title\":\"Customer\",\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"firstName\":{\"type\":\"string\"},\"lastName\":{\"type\":\"string\"},\"address\":{\"$ref\":\"address.schema.json\"}},\"required\":[\"firstName\",\"lastName\",\"address\"]}",
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
playground topic produce --topic json-schema-alltypes --forced-value '{"firstName":"dolor","lastName":"tempor occaecat in","address":{"street":"id","street2":"anim esse commodo sint","city":"aute aliqua in tempor","postalCode":"in consectetur laborum","countryCode":"deserunt ex"}}' --value-schema-id 3 << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "address.schema.json",
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
