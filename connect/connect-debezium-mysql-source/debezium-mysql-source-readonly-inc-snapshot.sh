#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-ro-inc-snapshot.yml"


log "Create teams table"
docker exec -i mysql mysql --user=root --password=password --database=mydb << EOF
USE mydb;

CREATE TABLE team (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL
);


INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'kafka',
  'kafka@apache.org',
  NOW()
);

ALTER TABLE team AUTO_INCREMENT = 101;
describe team;
select * from team;
EOF

log "Adding an element to the table"
docker exec -i mysql mysql --user=root --password=password --database=mydb << EOF
USE mydb;

INSERT INTO team (
  name,
  email,
  last_modified
) VALUES (
  'another',
  'another@apache.org',
  NOW()
);
EOF

log "Create customers table"
docker exec -i mysql mysql --user=root --password=password --database=mydb << EOF
USE mydb;
CREATE TABLE customers (
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT,
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255) NOT NULL,
  last_modified DATETIME     NOT NULL
);


INSERT INTO customers (
  name,
  email,
  last_modified
) VALUES (
  'Roger',
  'roger@apache.org',
  NOW()
);

INSERT INTO customers (
  name,
  email,
  last_modified
) VALUES (
  'James',
  'james@apache.org',
  NOW()
);

ALTER TABLE customers AUTO_INCREMENT = 101;
EOF


log "Creating Debezium MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.mysql.MySqlConnector",
                    "tasks.max": "1",
                    "database.hostname": "mysql",
                    "database.port": "3306",
                    "database.user": "debezium",
                    "database.password": "dbz",
                    "database.server.id": "223344",

                    "database.names" : "mydb",
                    "_comment": "old version before 2.x",
                    "database.server.name": "server1",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.mydb",
                    "_comment": "new version since 2.x",
                    "topic.prefix": "server1",
                    "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
                    "schema.history.internal.kafka.topic": "schema-changes.mydb",

                    "table.include.list": "mydb.team",
                    "transforms": "RemoveDots",
                    "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
                    "transforms.RemoveDots.replacement": "$1_$2_$3"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verifying topic server1_mydb_team"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1_mydb_team --from-beginning --max-messages 2

log "Show content of customer table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from customers'"

log "Adding customers table to the connector"

curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.mysql.MySqlConnector",
                    "tasks.max": "1",
                    "database.hostname": "mysql",
                    "database.port": "3306",
                    "database.user": "debezium",
                    "database.password": "dbz",
                    "database.server.id": "223344",
                    "database.server.name": "server1",

                    "database.names" : "mydb",
                    "_comment": "old version before 2.x",
                    "database.server.name": "server1",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.mydb",
                    "_comment": "new version since 2.x",
                    "topic.prefix": "server1",
                    "schema.history.internal.kafka.bootstrap.servers": "broker:9092",
                    "schema.history.internal.kafka.topic": "schema-changes.mydb",

                    "table.include.list": "mydb.team,mydb.customers",
                    "read.only": "true",
                    "signal.kafka.topic": "dbz-signals",
                    "signal.kafka.bootstrap.servers": "broker:9092",
                    "transforms": "RemoveDots",
                    "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
                    "transforms.RemoveDots.replacement": "$1_$2_$3"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

log "insert a record in customers"
docker exec -i mysql mysql --user=root --password=password --database=mydb << EOF
INSERT INTO customers (
  name,
  email,
  last_modified
) VALUES (
  'Roger',
  'roger@apache.org',
  NOW()
);
EOF

set +e
log "Verifying topic server1_mydb_customers : there will be only the new record"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1_mydb_customers --from-beginning --max-messages 3
set -e

log "Send Signal to the topic to start incremental snapshot"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --property "parse.key=true" --property "key.serializer=org.apache.kafka.common.serialization.StringSerializer" --property "key.separator=;" --topic dbz-signals --property "value.serializer=org.apache.kafka.common.serialization.StringSerializer" << EOF
server1;{"type":"execute-snapshot","data": {"data-collections": ["mydb.customers"], "type": "INCREMENTAL"}}
EOF

sleep 20

log "Verifying topic server1_mydb_customer again, the 3 records are there"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1_mydb_customers --from-beginning --max-messages 3
