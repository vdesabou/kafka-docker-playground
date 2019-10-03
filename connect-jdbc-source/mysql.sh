#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../nosecurity/start.sh "${PWD}/docker-compose.nosecurity.yml"

echo "Describing the application table in DB 'db':"
docker container exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe application'"

echo "Show content of application table:"
docker container exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

echo "Adding an element to the table"
docker container exec mysql mysql --user=root --password=password --database=db -e "
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

echo "Show content of application table:"
docker container exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

echo "Creating MySQL source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "mysql-source",
               "config": {
                    "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"10",
                    "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 5

echo "Verifying topic mysql-application"
docker container exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic mysql-application --from-beginning --max-messages 2


