#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if [ ! -z "$SQL_DATAGEN" ]
then
     log "🌪️ SQL_DATAGEN is set"
     for component in mysql-datagen
     do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component "
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
     done
else
     log "🛑 SQL_DATAGEN is not set"
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
playground connector create-or-update --connector debezium-mysql-source << EOF
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
              "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
              "transforms.RemoveDots.replacement": "$1_$2_$3"
          }
EOF

sleep 5

log "Verifying topic server1_mydb_team"
playground topic consume --topic server1_mydb_team --min-expected-messages 2 --timeout 60

if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=10
     log "Injecting data for $DURATION minutes"
     docker exec -d sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --connectionUrl 'jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false' --maxPoolSize 10 --durationTimeMin $DURATION"
fi

