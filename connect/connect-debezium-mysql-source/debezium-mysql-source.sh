#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Describing the team table in DB 'mydb':"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe team'"

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

log "Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=mydb -e "
INSERT INTO team (   \
  id,   \
  name, \
  email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
); "

log "Show content of team table:"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

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
                    "transforms": "RemoveDots",
                    "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
                    "transforms.RemoveDots.replacement": "$1_$2_$3"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

log "Verifying topic dbserver1_mydb_team"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic dbserver1_mydb_team --from-beginning --max-messages 2


