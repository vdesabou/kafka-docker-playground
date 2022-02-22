#!/bin/bash
set -e

export TAG=5.5.1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/postgresql-9.4.1207.jre7.jar ]
then
     wget https://repo1.maven.org/maven2/org/postgresql/postgresql/9.4.1207.jre7/postgresql-9.4.1207.jre7.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro.yml"

log "Create table drivers"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
CREATE SEQUENCE rownum_seq;
CREATE TABLE IF NOT EXISTS drivers (
    rownum INT DEFAULT nextval('rownum_seq'),
    id STRING NOT NULL,
    city STRING NOT NULL,
    name STRING,
    dl STRING,
    address STRING,
    INDEX name_idx (name),
    CONSTRAINT "primary" PRIMARY KEY (city ASC, id ASC),
    updated_at TIMESTAMPTZ
);
EOF

log "Creating JDBC CockroachDB source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max": "1",
               "connection.url": "jdbc:postgresql://cockroachdb:26257/defaultdb?user=root&sslmode=disable",
               "table.whitelist": "drivers",
               "mode": "timestamp",
               "timestamp.column.name": "updated_at",
               "timestamp.delay.interval.ms": "15000",
               "dialect.name": "PostgreSqlDatabaseDialect",
               "topic.prefix": "cockroachdb-",
               "validate.non.null":"false",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/cockroachdb-source/config | jq .

uuid1=$(uuidgen)
uuid2=$(uuidgen)
# FIXTHIS: works only with Linux
TIMESTAMP=`date --rfc-3339=seconds`

log "Adding 2 elements to the table with timestamp $TIMESTAMP"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
INSERT INTO drivers (id,city,name,dl,address,updated_at) VALUES
    ('$uuid1', 'seattle', 'Eric', 'GHI-9123', '400 Broad St',TIMESTAMPTZ '$TIMESTAMP'),
    ('$uuid2', 'new york', 'Harry Potter', 'JKL-456', '214 W 43rd St',TIMESTAMPTZ '$TIMESTAMP');
EOF

log "Show content of CUSTOMERS table:"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
SELECT * FROM drivers;
EOF

sleep 5

uuid1=$(uuidgen)
uuid2=$(uuidgen)
log "Adding 2 elements to the table with timestamp $TIMESTAMP"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
INSERT INTO drivers (id,city,name,dl,address,updated_at) VALUES
    ('$uuid1', 'Paris', 'paul', 'GHI-9123', '400 Broad St',TIMESTAMPTZ '$TIMESTAMP'),
    ('$uuid2', 'Madrid', 'jay', 'JKL-456', '214 W 43rd St',TIMESTAMPTZ '$TIMESTAMP');
EOF

sleep 5

log "Verifying topic cockroachdb-drivers: expecting 4 records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic cockroachdb-drivers --from-beginning --max-messages 4

log "Display connect-offsets"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1

uuid1=$(uuidgen)
uuid2=$(uuidgen)
TIMESTAMP=`date --rfc-3339=seconds`

log "Adding 2 elements to the table with timestamp $TIMESTAMP"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
INSERT INTO drivers (id,city,name,dl,address,updated_at) VALUES
    ('$uuid1', 'LA', 'Eric', 'GHI-9123', '400 Broad St',TIMESTAMPTZ '$TIMESTAMP'),
    ('$uuid2', 'Sidney', 'Harry Potter', 'JKL-456', '214 W 43rd St',TIMESTAMPTZ '$TIMESTAMP');
EOF

log "Show content of CUSTOMERS table:"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
SELECT * FROM drivers;
EOF
log "Display connect-offsets"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1

log "Pause the connector"
curl --request PUT \
  --url http://localhost:8083/connectors/cockroachdb-source/pause

uuid1=$(uuidgen)
uuid2=$(uuidgen)
log "Adding 2 elements to the table with timestamp $TIMESTAMP"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
INSERT INTO drivers (id,city,name,dl,address,updated_at) VALUES
    ('$uuid1', 'Nice', 'vincent', 'GHI-9123', '400 Broad St',TIMESTAMPTZ '$TIMESTAMP'),
    ('$uuid2', 'Marseille', 'Alex', 'JKL-456', '214 W 43rd St',TIMESTAMPTZ '$TIMESTAMP');
EOF

log "Show content of CUSTOMERS table:"
docker exec -i cockroachdb /cockroach/cockroach sql --insecure << EOF
SELECT * FROM drivers;
EOF
log "Display connect-offsets"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1

log "Restart task"
curl --request POST \
  --url http://localhost:8083/connectors/cockroachdb-source/tasks/0/restart

log "Resume the connector"
curl --request PUT \
  --url http://localhost:8083/connectors/cockroachdb-source/resume

log "Display connect-offsets"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1

sleep 5

log "Verifying topic cockroachdb-drivers: expecting 8 records"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic cockroachdb-drivers --from-beginning --max-messages 8

