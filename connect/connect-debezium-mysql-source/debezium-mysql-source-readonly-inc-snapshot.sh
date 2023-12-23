#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext-ro-inc-snapshot.yml"


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
playground connector create-or-update --connector debezium-mysql-source --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
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

  "table.include.list": "mydb.team",
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

log "Verifying topic server1_mydb_team"
playground topic consume --topic server1_mydb_team --min-expected-messages 2 --timeout 60

log "Show content of customer table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from customers'"

log "Adding customers table to the connector"

playground connector create-or-update --connector debezium-mysql-source --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
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
  "transforms.RemoveDots.regex": "(.*)\\\\.(.*)\\\\.(.*)",
  "transforms.RemoveDots.replacement": "\$1_\$2_\$3"
  }
EOF

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
playground topic consume --topic server1_mydb_customers --min-expected-messages 3 --timeout 60
set -e

log "Send Signal to the topic to start incremental snapshot"
playground topic produce -t dbz-signals --nb-messages 1 --key "server1" << 'EOF'
{"type":"execute-snapshot","data": {"data-collections": ["mydb.customers"], "type": "INCREMENTAL"}}
EOF

sleep 20

log "Verifying topic server1_mydb_customer again, the 3 records are there"
playground topic consume --topic server1_mydb_customers --min-expected-messages 3 --timeout 60
