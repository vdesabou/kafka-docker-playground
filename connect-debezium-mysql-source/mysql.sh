#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
${DIR}/../WaitForConnectAndControlCenter.sh

echo "Describing the team table in DB 'mydb':"
docker container exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe team'"

echo "Show content of team table:"
docker container exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

echo "Adding an element to the table"
docker container exec mysql mysql --user=root --password=password --database=mydb -e "
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

echo "Show content of team table:"
docker container exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

echo "Creating MySQL source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "debezium-mysql-source",
               "config": {
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
                    "database.history.kafka.topic": "schema-changes.mydb"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Verifying topic dbserver1.mydb.team"
docker container exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic dbserver1.mydb.team --from-beginning --max-messages 2


