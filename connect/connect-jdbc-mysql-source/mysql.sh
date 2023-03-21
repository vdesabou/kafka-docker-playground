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

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

log "Creating MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"10",
               "connection.url":"jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false",
               "table.whitelist":"team",
               "mode":"timestamp+incrementing",
               "timestamp.column.name":"last_modified",
               "incrementing.column.name":"id",
               "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql-source/config | jq .

sleep 5

log "Verifying topic mysql-team"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mysql-team --from-beginning --max-messages 2


