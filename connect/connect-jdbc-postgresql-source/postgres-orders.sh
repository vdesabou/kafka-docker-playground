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

# a table of your own, with its own load for playground connector benchmark: benchmark-load-orders.bash (the
# benchmark-load.bash of the folder loads the CUSTOMERS table of postgres.sh)

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create ORDERS table"
playground container exec --container postgres --command "psql -U myuser -d postgres" << EOF
CREATE TABLE orders (
        id SERIAL PRIMARY KEY,
        customer_id INT NOT NULL,
        product VARCHAR(50),
        quantity INT,
        price NUMERIC(10,2),
        created_ts timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO orders (customer_id, product, quantity, price) VALUES (1, 'kafka t-shirt', 2, 19.90);
INSERT INTO orders (customer_id, product, quantity, price) VALUES (2, 'connect mug', 1, 9.50);
INSERT INTO orders (customer_id, product, quantity, price) VALUES (3, 'playground sticker', 10, 0.99);
EOF

log "Creating JDBC PostgreSQL source connector on the ORDERS table"
playground connector create-or-update --connector postgres-orders-source --wait << EOF
{
     "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max": "1",
     "connection.url": "jdbc:postgresql://postgres:5432/postgres?user=myuser&password=mypassword&ssl=false",
     "table.whitelist": "orders",
     "mode": "incrementing",
     "incrementing.column.name": "id",
     "topic.prefix": "postgres-",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF

log "Verifying topic postgres-orders"
playground topic consume --topic postgres-orders --min-expected-messages 3 --timeout 60

log "🏎️ benchmark it with its own load: BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --nb-records 1000000"
