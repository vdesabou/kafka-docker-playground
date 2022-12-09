#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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
  id,
  name,
  email,
  last_modified
) VALUES (
  1,
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
  id,
  name,
  email,
  last_modified
) VALUES (
  2,
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
  id,
  name,
  email,
  last_modified
) VALUES (
  1,
  'Roger',
  'roger@apache.org',
  NOW()
);

INSERT INTO customers (
  id,
  name,
  email,
  last_modified
) VALUES (
  2,
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
                    "database.server.name": "dbserver1",
                    "database.whitelist": "mydb",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.mydb",
                    "table.include.list": "mydb.team",
                    "transforms": "RemoveDots",
                    "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
                    "transforms.RemoveDots.replacement": "$1_$2_$3"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verifying topic dbserver1_mydb_team"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_team --from-beginning --max-messages 2

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
                    "database.server.name": "dbserver1",
                    "database.whitelist": "mydb",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.mydb",
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
     
set +e
log "Verifying topic dbserver1_mydb_customers : it should be empty"
timeout 20 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_customers --from-beginning --max-messages 1
set -e

log "Send Signal to the topic to start incremental snapshot"
docker exec -i connect kafka-console-producer --broker-list broker:9092 --property "parse.key=true" --property "key.serializer=org.apache.kafka.common.serialization.StringSerializer" --property "key.separator=;" --topic dbz-signals --property "value.serializer=org.apache.kafka.common.serialization.StringSerializer" << EOF
dbserver1;{"type":"execute-snapshot","data": {"data-collections": ["mydb.customers"], "type": "INCREMENTAL"}}
EOF

sleep 20

log "Verifying topic dbserver1_mydb_customer again "
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_customers --from-beginning --max-messages 2
