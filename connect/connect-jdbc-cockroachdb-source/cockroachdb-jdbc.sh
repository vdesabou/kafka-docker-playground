#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.7.99"
then
     logwarn "minimal supported connector version is 10.8.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create table drivers"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
CREATE SEQUENCE rownum_seq;
CREATE TABLE IF NOT EXISTS drivers (
    rownum INT DEFAULT nextval('rownum_seq'),
    id UUID NOT NULL,
    city STRING NOT NULL,
    name STRING,
    dl STRING,
    address STRING,
    INDEX name_idx (name),
    CONSTRAINT "primary" PRIMARY KEY (city ASC, id ASC)
);
EOF

log "Adding 2 elements to the table"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
INSERT INTO drivers (id,city,name,dl,address) VALUES
    ('8a3d70a3-d70a-4000-8000-00000000001b', 'seattle', 'Eric', 'GHI-9123', '400 Broad St'),
    ('9eb851eb-851e-4800-8000-00000000001f', 'new york', 'Harry Potter', 'JKL-456', '214 W 43rd St');
EOF

log "Show content of CUSTOMERS table:"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
SELECT * FROM drivers;
EOF

log "Creating JDBC CockroachDB source connector"
playground connector create-or-update --connector cockroachdb-source  << EOF
{
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "tasks.max": "1",
    "connection.url": "jdbc:postgresql://cockroachdb:26257/defaultdb?user=root&sslmode=disable",
    "table.whitelist": "drivers",
    "mode": "incrementing",
    "incrementing.column.name": "rownum",
    "topic.prefix": "cockroachdb-",
    "validate.non.null":"false",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF


sleep 5

log "Verifying topic cockroachdb-drivers"
playground topic consume --topic cockroachdb-drivers --min-expected-messages 2 --timeout 60


