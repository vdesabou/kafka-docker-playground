#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# Debezium SMTs ship inside the Debezium connector, so here CONNECTOR_TAG = the Debezium connector
# version (which carries the SMT) — the version guard below is correct for this carrier.
# TimezoneConverter itself needs Debezium >= 2.4, covered by the CP 8 guard (>= 2.5.0).
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

log "Create a table with a timestamptz column"
playground container exec --container postgres --command "psql -U myuser -d postgres" << EOF
create table tz_test (
    id int primary key,
    created_at timestamptz
);
EOF

log "Creating Debezium PostgreSQL source connector with the Debezium TimezoneConverter SMT (io.debezium.transforms) converting temporal fields to the +05:30 offset"
playground connector create-or-update --connector debezium-timezoneconverter-source  << EOF
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
     "table.include.list": "public.tz_test",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",

     "transforms": "tzConverter",
     "transforms.tzConverter.type": "io.debezium.transforms.TimezoneConverter",
     "transforms.tzConverter.converted.timezone": "+05:30"
}
EOF

sleep 5

log "Insert a row with a known UTC timestamp (2023-01-01 12:00:00+00 -> should become 17:30:00+05:30)"
playground container exec --container postgres --command "psql -U myuser -d postgres" << EOF
insert into tz_test (id, created_at) values (1, '2023-01-01 12:00:00+00');
EOF

log "Verify TimezoneConverter converted the timestamptz field to the +05:30 offset (default Debezium output would be UTC 'Z')"
playground topic consume --topic dbz.public.tz_test --min-expected-messages 1 --max-messages 1 --timeout 60 | tee /tmp/smt-timezoneconverter-consume.txt

grep "+05:30" /tmp/smt-timezoneconverter-consume.txt
log "TimezoneConverter SMT applied: timestamptz converted to the +05:30 offset"
