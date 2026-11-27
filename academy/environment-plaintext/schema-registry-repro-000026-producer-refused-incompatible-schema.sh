#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}"

log "Version 1 of the customer service: name and email"
playground topic produce -t customers --nb-messages 3 << 'EOF'
{
  "type": "record",
  "namespace": "com.example",
  "name": "Customer",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "email", "type": "string"}
  ]
}
EOF

log "Version 2 of the customer service: a new field, loyalty_tier"
set +e
playground topic produce -t customers --nb-messages 3 << 'EOF'
{
  "type": "record",
  "namespace": "com.example",
  "name": "Customer",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "email", "type": "string"},
    {"name": "loyalty_tier", "type": "string"}
  ]
}
EOF
set -e

playground topic get-offsets --topic customers || true
