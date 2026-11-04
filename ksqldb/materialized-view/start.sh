#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.4.99"; then
    logwarn "This example with connectors works since CP 5.5 only"
    exit 111
fi

# make sure ksqlDB is not disabled
export ENABLE_KSQLDB=true

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Describing the calls table in DB 'mydb':"
playground db sql --database mydb << 'EOF'
describe calls;
EOF

log "Show content of calls table:"
playground db sql --database mydb << 'EOF'
select * from calls;
EOF


log "Create source connector"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE SOURCE CONNECTOR calls_reader WITH (
    'connector.class' = 'io.debezium.connector.mysql.MySqlConnector',
    'database.hostname' = 'mysql',
    'database.port' = '3306',
    'database.user' = 'debezium',
    'database.password' = 'dbz',
    'database.allowPublicKeyRetrieval' = 'true',
    'database.server.id' = '223344',
    'table.whitelist' = 'mydb.calls',

    'database.names'  = 'mydb',
    '_comment' = 'old version before 2.x',
    'database.server.name' = 'dbserver1',
    'database.history.kafka.bootstrap.servers' = 'broker:9092',
    'database.history.kafka.topic' = 'call-center',
    '_comment 2' = 'new version since 2.x',
    'topic.prefix' = 'dbserver1',
    'schema.history.internal.kafka.bootstrap.servers' = 'broker:9092',
    'schema.history.internal.kafka.topic' = 'call-center',

    'include.schema.changes' = 'false'
);
EOF

playground topic wait-for-records --topic dbserver1.mydb.calls --min-expected-messages 1 --max-wait 120

log "Check topic"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

SHOW TOPICS;
PRINT 'dbserver1.mydb.calls' FROM BEGINNING LIMIT 10;
DESCRIBE CONNECTOR calls_reader;
EOF

log "Create the ksqlDB calls stream"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM calls WITH (
    kafka_topic = 'dbserver1.mydb.calls',
    value_format = 'avro'
);
EOF


log "Create the materialized views"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE TABLE support_view AS
    SELECT after->name AS name,
           count_distinct(after->reason) AS distinct_reasons,
           latest_by_offset(after->reason) AS last_reason
    FROM calls
    GROUP BY after->name
    EMIT CHANGES;

CREATE TABLE lifetime_view AS
    SELECT after->name AS name,
           count(after->reason) AS total_calls,
           (sum(after->duration_seconds) / 60) as minutes_engaged
    FROM calls
    GROUP BY after->name
    EMIT CHANGES;
EOF

playground ksqldb wait

if ! version_gt $TAG_BASE "5.9.9"; then
    # with 5.5.x, we need to use ROWKEY
    log "Query the materialized views"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

SELECT name, distinct_reasons, last_reason
FROM support_view
WHERE ROWKEY = 'derek';

SELECT name, total_calls, minutes_engaged
FROM lifetime_view
WHERE ROWKEY = 'michael';
EOF
else
    log "Query the materialized views"
playground ksqldb sql << EOF

SET 'auto.offset.reset' = 'earliest';

SELECT name, distinct_reasons, last_reason
FROM support_view
WHERE name = 'derek';

SELECT name, total_calls, minutes_engaged
FROM lifetime_view
WHERE name = 'michael';
EOF
fi




log "Verifying topic dbserver1.mydb.calls"
playground topic consume --topic dbserver1.mydb.calls --min-expected-messages 2 --timeout 60


