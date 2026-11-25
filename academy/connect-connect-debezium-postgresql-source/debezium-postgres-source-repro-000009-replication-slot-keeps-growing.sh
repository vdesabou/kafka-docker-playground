#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.4.99"
then
     logwarn "minimal supported connector version is 2.5.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000009-replication-slot-keeps-growing.yml"

log "Creating the tables: customers (captured by the connector) and audit_log (another application writes there)"
playground db sql << 'EOF'
CREATE TABLE customers (id SERIAL PRIMARY KEY, first_name VARCHAR(50), last_name VARCHAR(50), email VARCHAR(50));
INSERT INTO customers (first_name, last_name, email) VALUES ('Rica', 'Blaisdell', 'rblaisdell0@example.com');
INSERT INTO customers (first_name, last_name, email) VALUES ('Ruthie', 'Brockherst', 'rbrockherst1@example.com');
INSERT INTO customers (first_name, last_name, email) VALUES ('Mariejeanne', 'Cocci', 'mcocci2@example.com');
CREATE TABLE audit_log (id BIGINT, payload TEXT, created_at TIMESTAMP);
EOF

log "Creating Debezium PostgreSQL source connector: only table customers"
playground connector create-or-update --connector debezium-postgres-source << EOF
{
     "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
     "tasks.max": "1",
     "database.hostname": "postgres",
     "database.port": "5432",
     "database.user": "myuser",
     "database.password": "mypassword",
     "database.dbname" : "postgres",
     "topic.prefix": "asgard",
     "plugin.name": "pgoutput",
     "slot.name": "debezium",
     "publication.autocreate.mode": "filtered",
     "table.include.list": "public.customers",
     "key.converter": "org.apache.kafka.connect.json.JsonConverter",
     "key.converter.schemas.enable": "false",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOF

playground topic consume --topic asgard.public.customers --min-expected-messages 3 --timeout 60

# the issue: the database is busy, but not with the table of the connector
log "Another application writes a lot in table audit_log (not captured)"
for i in 1 2 3
do
playground db sql << 'EOF'
INSERT INTO audit_log SELECT g, md5(g::text) || md5((g + 1)::text) || md5((g + 2)::text), now() FROM generate_series(1, 300000) g;
EOF
done
sleep 30

log "The connector is RUNNING..."
playground connector status --connector debezium-postgres-source

log "...but the disk of the database keeps filling up:"
playground db sql << 'EOF'
SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS retained_wal FROM pg_replication_slots;
EOF
