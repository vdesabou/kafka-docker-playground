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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000015-renamed-connector-rereads-topic.yml"

log "Creating JDBC PostgreSQL sink connector sink-1"
playground connector create-or-update --connector sink-1 << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
EOF

log "Sending 10 orders"
playground topic produce -t orders --nb-messages 10 << 'EOF'
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

playground db wait-for-rows --table orders --min-expected-rows 10

# the issue: the team renames its connectors to follow a naming convention (Connect has no rename: delete, then create)
log "Renaming sink-1 to postgres-orders-sink"
playground connector delete --connector sink-1
playground connector create-or-update --connector postgres-orders-sink << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
EOF

sleep 15

log "The table:"
playground db sql << 'EOF'
SELECT count(*) AS nb_rows, count(DISTINCT id) AS nb_orders FROM orders;
EOF
