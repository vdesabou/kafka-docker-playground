#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

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
playground topic produce --topic protobuf-alltypes --forced-value '{"firstName":"Gupdqph.","lastName":"Ovck aobggjqdzn.","address":{"street":"Pchhblish rnsvtvwg ozjizdo.","street2":"Oyxp ybbtddn.","city":"Spqkjlihb qqsmiwufn tewcgudxt.","state":"Fwbwky yqvzcw viio fqsehza.","postalCode":"Wooxyyx slnr wmbf.","countryCode":"Ycfpnnh oknlsgup dczjgouyo edevdbuong."}}' --value-schema-id 3 << 'EOF'
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