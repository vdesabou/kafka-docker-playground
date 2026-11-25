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
# the compose file of the JDBC PostgreSQL sink example (postgres and the JDBC plugin), used as is
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${DIR}/../../connect/connect-jdbc-postgresql-sink/docker-compose.plaintext.yml"

log "Creating table orders"
playground db sql << 'EOF'
CREATE TABLE orders (id INT PRIMARY KEY, product TEXT, quantity INT, price REAL);
EOF

# the issue: another application opened a transaction on the table and never ended it (a batch job that hangs, a
# forgotten psql session...). Its SHARE lock lets SELECT run, but makes every INSERT wait until the transaction ends
log "Starting the nightly-batch session: a transaction that locks table orders and stays open"
docker exec -d postgres bash -c "(echo 'BEGIN; LOCK TABLE orders IN SHARE MODE;'; sleep 3600) | PGAPPNAME=nightly-batch psql -U myuser -d postgres"
sleep 2

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

log "Sending 10 messages to topic orders"
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

sleep 15

log "The connector is RUNNING..."
playground connector status --connector postgres-sink

log "...but table orders is still empty: why?"
playground db sql << 'EOF'
SELECT count(*) FROM orders;
EOF
