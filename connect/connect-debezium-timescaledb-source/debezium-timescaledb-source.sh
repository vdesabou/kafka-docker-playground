#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.4.99"
then
     logwarn "minimal supported connector version is 2.5.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi


PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Debezium PostgreSQL source connector with TimescaleDB"
playground connector create-or-update --connector debezium-timescaledb-source  << EOF
{
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "timescaledb",
    "database.port": "5432",
    "database.user": "postgres",
    "database.password": "postgres",
    "database.dbname" : "postgres",
    "plugin.name": "pgoutput",

    "_comment": "old version before 2.x",
    "database.server.name": "timescaledb",
    "_comment": "new version since 2.x",
    "topic.prefix": "timescaledb",

    "schema.include.list": "_timescaledb_internal",

    "key.converter" : "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter" : "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",


    "transforms": "timescaledb",
    "transforms.timescaledb.type": "io.debezium.connector.postgresql.transforms.timescaledb.TimescaleDb",
    "transforms.timescaledb.database.hostname": "timescaledb",
    "transforms.timescaledb.database.port": "5432",
    "transforms.timescaledb.database.user": "postgres",
    "transforms.timescaledb.database.password": "postgres",
    "transforms.timescaledb.database.dbname": "postgres",


    "_comment:": "remove _ to use ExtractNewRecordState smt",
    "_transforms": "timescaledb,addTopicSuffix",
    "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF


sleep 5

log "Adding an element to the table"
docker exec -e PGOPTIONS="--search_path=public" -i timescaledb psql -U postgres -d postgres << EOF
INSERT INTO conditions VALUES (now(), 'Prague', 30, 50);
EOF

log "Show content of conditions table:"
docker exec -e PGOPTIONS="--search_path=public" -i timescaledb psql -U postgres -d postgres << EOF
SELECT * FROM conditions;
EOF

log "Verifying topic timescaledb.public.conditions"
playground topic consume --topic timescaledb.public.conditions --min-expected-messages 2 --timeout 60