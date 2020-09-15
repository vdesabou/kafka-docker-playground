#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -d confluent-hub-components ]
then
     mkdir -p confluent-hub-components
     confluent-hub install --component-dir confluent-hub-components --no-prompt debezium/debezium-connector-mysql:1.1.0
fi

${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Describing the calls table in DB 'mydb':"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe calls'"

log "Show content of calls table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from calls'"


log "Create source connector"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE SOURCE CONNECTOR calls_reader WITH (
    'connector.class' = 'io.debezium.connector.mysql.MySqlConnector',
    'database.hostname' = 'mysql',
    'database.port' = '3306',
    'database.user' = 'debezium',
    'database.password' = 'dbz',
    'database.allowPublicKeyRetrieval' = 'true',
    'database.server.id' = '223344',
    'database.server.name' = 'dbserver1',
    'database.whitelist' = 'mydb',
    'database.history.kafka.bootstrap.servers' = 'broker:9092',
    'database.history.kafka.topic' = 'call-center',
    'table.whitelist' = 'mydb.calls',
    'include.schema.changes' = 'false'
);
EOF

sleep 5

log "Check topic"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

SHOW TOPICS;
PRINT 'dbserver1.mydb.calls' FROM BEGINNING LIMIT 10;
DESCRIBE CONNECTOR calls_reader;
EOF

log "Create the ksqlDB calls stream"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

CREATE STREAM calls WITH (
    kafka_topic = 'dbserver1.mydb.calls',
    value_format = 'avro'
);
EOF


log "Create the materialized views"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

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

sleep 5

log "Query the materialized views"
timeout 120 docker exec -i ksqldb-cli bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksqldb-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksqldb-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksqldb-server:8088' << EOF

SET 'auto.offset.reset' = 'earliest';

SELECT name, distinct_reasons, last_reason
FROM support_view
WHERE name = 'derek';

SELECT name, total_calls, minutes_engaged
FROM lifetime_view
WHERE name = 'michael';
EOF


# log "Adding an element to the table"
# docker exec mysql mysql --user=root --password=password --database=mydb -e "
# INSERT INTO calls (   \
#   id,   \
#   name, \
#   email,   \
#   last_modified \
# ) VALUES (  \
#   2,    \
#   'another',  \
#   'another@apache.org',   \
#   NOW() \
# ); "

# log "Show content of calls table:"
# docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from calls'"

# log "Creating Debezium MySQL source connector"
# curl -X PUT \
#      -H "Content-Type: application/json" \
#      --data '{
#                "connector.class": "io.debezium.connector.mysql.MySqlConnector",
#                     "tasks.max": "1",
#                     "database.hostname": "mysql",
#                     "database.port": "3306",
#                     "database.user": "debezium",
#                     "database.password": "dbz",
#                     "database.server.id": "223344",
#                     "database.server.name": "dbserver1",
#                     "database.whitelist": "mydb",
#                     "database.history.kafka.bootstrap.servers": "broker:9092",
#                     "database.history.kafka.topic": "schema-changes.mydb",
#                     "transforms": "RemoveDots",
#                     "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
#                     "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
#                     "transforms.RemoveDots.replacement": "$1_$2_$3"
#           }' \
#      http://localhost:8083/connectors/debezium-mysql-source/config | jq .

# sleep 5

# log "Verifying topic dbserver1_mydb_calls"
# timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_calls --from-beginning --max-messages 2


