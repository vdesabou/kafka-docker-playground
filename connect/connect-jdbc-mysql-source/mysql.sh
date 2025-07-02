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

cd ../../connect/connect-jdbc-mysql-source
if [ ! -f ${PWD}/mysql-connector-j-8.4.0.jar ]
then
     log "Downloading mysql-connector-j-8.4.0.jar"
     wget -q https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.4.0/mysql-connector-j-8.4.0.jar
fi
cd -

if [ ! -z "$SQL_DATAGEN" ]
then
     cd ../../connect/connect-jdbc-mysql-source
     log "🌪️ SQL_DATAGEN is set"
     for component in mysql-datagen
     do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "❌ failed to build java component "
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
     done
     cd -
else
     log "🛑 SQL_DATAGEN is not set"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

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

if [ ! -z "$SQL_DATAGEN" ]
then
     DURATION=1
     log "Injecting data for $DURATION minutes"
     docker exec sql-datagen bash -c "java ${JAVA_OPTS} -jar sql-datagen-1.0-SNAPSHOT-jar-with-dependencies.jar --connectionUrl 'jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false' --maxPoolSize 10 --durationTimeMin $DURATION"
fi

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

log "Creating MySQL source connector"
playground connector create-or-update --connector mysql-source << EOF
{
     "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
     "tasks.max":"1",
     "connection.url":"jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false",
     "table.whitelist":"team",
     "mode":"timestamp+incrementing",
     "timestamp.column.name":"last_modified",
     "incrementing.column.name":"id",
     "topic.prefix":"mysql-"
}
EOF

sleep 5

log "Verifying topic mysql-team"
playground topic consume --topic mysql-team --min-expected-messages 2 --timeout 60


