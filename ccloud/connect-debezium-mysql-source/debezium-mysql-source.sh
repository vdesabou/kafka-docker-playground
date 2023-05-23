#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     create_topic server1_mydb_team
     create_topic server1
     create_topic schema-changes.inventory
     set -e
fi


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
               "database.whitelist": "mydb",

               "_comment": "old version before 2.x",
               "database.server.name": "server1",
               "database.history.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "database.history.kafka.topic": "schema-changes.inventory",
               "database.history.producer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "database.history.producer.sasl.mechanism": "PLAIN",
               "database.history.producer.security.protocol": "SASL_SSL",
               "database.history.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "database.history.consumer.sasl.mechanism": "PLAIN",
               "database.history.consumer.security.protocol": "SASL_SSL",

               "_comment": "new version since 2.x",
               "database.encrypt": "false",
               "topic.prefix": "server1",
               "schema.history.internal.kafka.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "schema.history.internal.kafka.topic": "schema-changes.inventory",
               "schema.history.internal.producer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "schema.history.internal.producer.sasl.mechanism": "PLAIN",
               "schema.history.internal.producer.security.protocol": "SASL_SSL",
               "schema.history.internal.consumer.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "schema.history.internal.consumer.sasl.mechanism": "PLAIN",
               "schema.history.internal.consumer.security.protocol": "SASL_SSL",

               "transforms": "RemoveDots",
               "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
               "transforms.RemoveDots.replacement": "$1_$2_$3",
               "topic.creation.default.replication.factor": "-1",
               "topic.creation.default.partitions": "-1"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verifying topic server1_mydb_team"
playground topic consume --topic server1_mydb_team --min-expected-messages 2

