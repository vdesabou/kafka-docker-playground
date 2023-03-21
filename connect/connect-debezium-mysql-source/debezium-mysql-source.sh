#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Create table"
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

              "transforms": "RemoveDots",
              "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
              "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
              "transforms.RemoveDots.replacement": "$1_$2_$3"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verifying topic server1_mydb_team"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic server1_mydb_team --from-beginning --max-messages 2


