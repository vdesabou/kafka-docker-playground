#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     echo -e "\033[0;33mDownloading mysql-connector-java-5.1.45.jar\033[0m"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mDescribing the application table in DB 'db':\033[0m"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'describe application'"

echo -e "\033[0;33mShow content of application table:\033[0m"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

echo -e "\033[0;33mAdding an element to the table\033[0m"
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

echo -e "\033[0;33mShow content of application table:\033[0m"
docker exec mysql bash -c "mysql --user=root --password=password --database=db -e 'select * from application'"

echo -e "\033[0;33mCreating MySQL source connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"10",
                    "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql-source/config | jq .

sleep 5

echo -e "\033[0;33mVerifying topic mysql-application\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic mysql-application --from-beginning --max-messages 2


