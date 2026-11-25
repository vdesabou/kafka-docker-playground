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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000007-duplicates-after-worker-crash.yml"

log "Creating JDBC PostgreSQL sink connector"
playground connector create-or-update --connector postgres-sink  << EOF
{
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "1",
  "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
  "topics": "orders",
  "auto.create": "true"
}
EOF

log "Sending 10 orders to topic orders"
playground topic produce -t orders --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ]
}
EOF

playground db wait-for-rows --table orders --min-expected-rows 10

# the issue: the worker dies (an OOM kill, a node lost...) a few seconds after writing the rows, and is restarted
log "💥 The connect worker crashes, and is restarted"
playground container kill --container connect
playground container restart --container connect
playground container wait-for-connect-rest-api-ready
# the task joins its consumer group again once the member of the killed worker has timed out (session.timeout.ms, 45 s)
playground db wait-for-rows --table orders --min-expected-rows 20 --max-wait 180

log "The connector is RUNNING..."
playground connector status --connector postgres-sink

log "...the topic has 10 orders, but the table has:"
playground db sql << 'EOF'
SELECT count(*) FROM orders;
EOF
