#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

singlestore-wait-start() {
  log "Waiting for SingleStore to start..."
  while true; do
      if docker exec singlestore memsql -u root -proot -e "select 1" >/dev/null 2>/dev/null; then
          break
      fi
      log "."
      sleep 0.2
  done
  log "Success!"
}

cd ../../connect/connect-jdbc-singlestore-source
if [ ! -f ${PWD}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi
cd -

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Starting singlestore cluster"
docker start singlestore

singlestore-wait-start

log "Creating 'db' SingleStore database and table 'application'"
docker exec singlestore memsql -u root -proot -e "
CREATE DATABASE IF NOT EXISTS db;  \
USE db; \
CREATE TABLE IF NOT EXISTS application ( \
  id            INT          NOT NULL PRIMARY KEY AUTO_INCREMENT, \
  name          VARCHAR(255) NOT NULL, \
  team_email    VARCHAR(255) NOT NULL, \
  last_modified DATETIME     NOT NULL \
); \
INSERT INTO application ( \
  id, \
  name, \
  team_email, \
  last_modified \
) VALUES ( \
  1, \
  'kafka', \
  'kafka@apache.org', \
  NOW() \
);"


log "Describing the application table in DB 'db':"
docker exec singlestore memsql -u root -proot -e "USE db;describe application"

log "Show content of application table:"
docker exec singlestore memsql -u root -proot -e "USE db;select * from application"

log "Adding an element to the table"
docker exec singlestore memsql -u root -proot -e "USE db;
INSERT INTO application (   \
  id,   \
  name, \
  team_email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "

log "Show content of application table:"
docker exec singlestore memsql -u root -proot -e "USE db;select * from application"


log "Creating JDBC Singlestore source connector"
playground connector create-or-update --connector jdbc-singlestore-source << EOF
{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.url":"jdbc:mysql://singlestore:3306/db?user=root&password=root&useSSL=false",
               "table.whitelist":"application",
               "mode":"timestamp+incrementing",
               "timestamp.column.name":"last_modified",
               "incrementing.column.name":"id",
               "topic.prefix":"singlestore-"

          }
EOF

sleep 5

log "Verifying topic singlestore-application"
playground topic consume --topic singlestore-application --min-expected-messages 2 --timeout 60
