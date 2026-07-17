#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Debezium SMTs ship inside the Debezium connector, so here CONNECTOR_TAG = the Debezium connector
# version (which carries the SMT) — the version guard below is correct for this carrier.
if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.4.99"
then
     logwarn "minimal supported connector version is 2.5.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.debezium-postgres.yml"

log "Create the outbox table"
playground container exec --container postgres --command "psql -U myuser -d postgres" << EOF
create table outbox (
    id varchar(50) primary key,
    aggregatetype varchar(255),
    aggregateid varchar(255),
    type varchar(255),
    payload varchar(4000)
);
EOF

log "Creating Debezium PostgreSQL source connector with the Debezium EventRouter (outbox) SMT (io.debezium.transforms.outbox)"
playground connector create-or-update --connector debezium-eventrouter-source  << EOF
{
     "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
     "tasks.max": "1",
     "database.hostname": "postgres",
     "database.port": "5432",
     "database.user": "myuser",
     "database.password": "mypassword",
     "database.dbname": "postgres",
     "plugin.name": "pgoutput",
     "topic.prefix": "dbz",
     "table.include.list": "public.outbox",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",

     "transforms": "outbox",
     "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter"
}
EOF

sleep 5

log "Insert an outbox event (aggregatetype=customer) — EventRouter routes by this field to topic outbox.event.customer"
playground container exec --container postgres --command "psql -U myuser -d postgres" << EOF
insert into outbox (id, aggregatetype, aggregateid, type, payload) values ('11111111-1111-1111-1111-111111111111', 'customer', '1', 'CustomerCreated', '{"name":"EVENTROUTER_PAYLOAD"}');
EOF

log "Verify EventRouter routed the event to topic outbox.event.customer with the payload column as the record value"
playground topic consume --topic outbox.event.customer --min-expected-messages 1 --max-messages 1 --timeout 60 | tee /tmp/smt-eventrouter-consume.txt

grep "EVENTROUTER_PAYLOAD" /tmp/smt-eventrouter-consume.txt
log "EventRouter SMT applied: outbox event routed to outbox.event.customer"
