#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.9.99"
then
     logwarn "minimal supported connector version is 3.0.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create table"
playground container exec --container mysql --command "mysql  --protocol=TCP --host=127.0.0.1 --user=root --password=password --database=mydb" << EOF
USE mydb;

CREATE TABLE CUSTOMERS (
  id          INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  first_name  VARCHAR(50),
  last_name   VARCHAR(50),
  email       VARCHAR(50),
  gender      VARCHAR(50),
  club_status VARCHAR(20),
  comments    VARCHAR(90),
  create_ts   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  update_ts   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);


INSERT INTO CUSTOMERS (first_name, last_name, email, gender, club_status, comments) VALUES ('Rica', 'Blaisdell', 'rblaisdell0@rambler.ru', 'Female', 'bronze', 'Universal optimal hierarchy');

describe CUSTOMERS;
select * from CUSTOMERS;
EOF

log "Adding an element to the table"
playground container exec --container mysql --command "mysql  --protocol=TCP --host=127.0.0.1 --user=root --password=password --database=mydb" << EOF
USE mydb;

INSERT INTO CUSTOMERS (first_name, last_name, email, gender, club_status, comments) VALUES ('Ruthie', 'Brockherst', 'rbrockherst1@ow.ly', 'Female', 'platinum', 'Reverse-engineered tangible interface');
EOF

log "Creating Debezium MySQL source connector"
playground connector create-or-update --connector debezium-mysql-source  << EOF
{
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
  "transforms.RemoveDots.regex": "(.*)\\\\.(.*)\\\\.(.*)",
  "transforms.RemoveDots.replacement": "\$1_\$2_\$3",

  "_comment:": "remove _ to use ExtractNewRecordState smt",
  "_transforms": "unwrap,RemoveDots",
  "_transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState"
}
EOF

sleep 5

log "Verifying topic server1_mydb_CUSTOMERS"
playground topic consume --topic server1_mydb_CUSTOMERS --min-expected-messages 2 --timeout 60

