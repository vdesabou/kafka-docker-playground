#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ../../connect/connect-jdbc-mysql-source
if [ ! -f ${PWD}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi
cd -

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-000005-insertfield-smt:-adding-topic-offset-and-partition-not-working.yml"

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

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"


playground debug log-level set --package "org.apache.kafka.connect.runtime.TransformationChain" --level TRACE

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
               "topic.prefix":"mysql-",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true",
               "transforms": "InsertTopic,InsertOffset,InsertPartition,InsertTimestamp,TimestampConverter",
               "transforms.InsertOffset.offset.field": "__kafka_offset",
               "transforms.InsertOffset.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
               "transforms.InsertPartition.partition.field": "__kafka_partition",
               "transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
               "transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
               "transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
               "transforms.InsertTopic.topic.field": "__kafka_topic",
               "transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
               "transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter\$Value",
               "transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
               "transforms.TimestampConverter.target.type": "string",
               "transforms.TimestampConverter.field": "__kafka_ts"
          }
EOF

sleep 5

playground connector status

playground topic consume
