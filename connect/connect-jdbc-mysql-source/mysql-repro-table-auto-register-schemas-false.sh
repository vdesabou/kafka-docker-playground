#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-table-order-counts-for-schema.yml"

log "First DB"

log "DB #1: Describing the application table in DB 'db':"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe application'"

log "DB #1: Show content of application table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

log "DB #1: Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=db -e "
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

log "DB #1: Show content of application table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

# repro
log "Second DB"

log "DB #2: Describing the application table in DB 'db':"
docker exec mysql2 bash -c "mysql --user=root --password=password --database=db -e 'describe application'"

log "DB #2: Show content of application table:"
docker exec mysql2 bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

log "DB #2: Adding an element to the table"
docker exec mysql2 mysql --user=root --password=password --database=db -e "
INSERT INTO application (   \
  id,   \
  team_email,   \
  name, \
  last_modified \
) VALUES (  \
  2,    \
  'another@apache.org',   \
  'another',  \
  NOW() \
); "

log "DB #2: Show content of application table:"
docker exec mysql2 bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"


log "DB #1: Creating MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.connect.meta.data": "false",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql-source/config | jq .

sleep 5

log "Verifying topic mysql-application"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mysql-application --from-beginning --max-messages 2

log "DB #2: Creating MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.url":"jdbc:mysql://mysql2:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.connect.meta.data": "false",
                    "value.converter.auto.register.schemas" : "false",
                    "value.converter.use.latest.version": "true",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql2-source/config | jq .

sleep 5

log "Verifying topic mysql-application"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mysql-application --from-beginning --max-messages 4

# PROBLEM !
# {"id":1,"name":"kafka","team_email":"kafka@apache.org","last_modified":1603092523000}
# {"id":2,"name":"another","team_email":"another@apache.org","last_modified":1603092548000}
# {"id":1,"name":"kafka@apache.org","team_email":"kafka","last_modified":1603092523000}
# {"id":2,"name":"another@apache.org","team_email":"another","last_modified":1603092549000}

log "Checking that there is only 1 version"
curl http://localhost:8081/subjects/mysql-application-value/versions | jq .