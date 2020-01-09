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


echo -e "\033[0;33mDescribing the team table in DB 'mydb':\033[0m"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'describe team'"

echo -e "\033[0;33mShow content of team table:\033[0m"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

echo -e "\033[0;33mAdding an element to the table\033[0m"
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

echo -e "\033[0;33mShow content of team table:\033[0m"
docker exec mysql bash -c "mysql --user=root --password=password --database=mydb -e 'select * from team'"

echo -e "\033[0;33mCreating Debezium MySQL source connector\033[0m"
docker exec connect \
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
                    "database.history.kafka.topic": "schema-changes.mydb"
          }' \
     http://localhost:8083/connectors/debezium-mysql-source/config | jq .

sleep 5

echo -e "\033[0;33mVerifying topic dbserver1.mydb.team\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic dbserver1.mydb.team --from-beginning --max-messages 2


