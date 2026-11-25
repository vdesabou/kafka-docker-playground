#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000010-incompatible-schema-breaks-sink.yml"

log "Creating JDBC PostgreSQL sink connector"
playground connector create-or-update --connector postgres-sink  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true",
  "auto.evolve": "true"
}
EOF

log "Sending 5 orders (schema version 1: quantity is an int)"
playground topic produce -t orders --nb-messages 5 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "product", "type": "string"},
    {"name": "quantity", "type": "int"},
    {"name": "price", "type": "float"}
  ]
}
EOF

playground db wait-for-rows --table orders --min-expected-rows 5

# the issue: someone relaxed the compatibility of the subject to deploy a change faster...
playground schema set-compatibility --subject orders-value --compatibility NONE
# ...and a new version of the producer sends quantity as a string ("3 boxes")
log "A new version of the producer sends 5 more orders"
playground topic produce -t orders --nb-messages 5 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "product", "type": "string"},
    {"name": "quantity", "type": "string"},
    {"name": "price", "type": "float"}
  ]
}
EOF

# the JDBC sink retries a failed write 10 times, 3 seconds apart, before it fails the task
sleep 45

log "The connector:"
playground connector status --connector postgres-sink
