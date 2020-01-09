#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-wal2json-noissue.yml"

#################
# This test is using debezium/postgres:10
# which is using wal2json dated from 11 Dec 2018 (including fix for https://issues.jboss.org/browse/DBZ-842 / https://github.com/eulerto/wal2json/issues/74)
#################
    # using this image we get no issue

echo -e "\033[0;33mShow content of CUSTOMERS table:\033[0m"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo -e "\033[0;33mAdding an element to the table\033[0m"

docker exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

echo -e "\033[0;33mShow content of CUSTOMERS table:\033[0m"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo -e "\033[0;33mCreating Debezium PostgreSQL source connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                    "plugin.name": "wal2json",
                    "tasks.max": "1",
                    "database.hostname": "postgres",
                    "database.port": "5432",
                    "database.user": "postgres",
                    "database.password": "postgres",
                    "database.dbname" : "postgres",
                    "database.server.name": "asgard",
                    "database.history.kafka.bootstrap.servers": "broker:9092",
                    "database.history.kafka.topic": "schema-changes.postgres",
                    "transforms": "addTopicSuffix",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .



sleep 5

echo -e "\033[0;33mUpdating elements to the table\033[0m"

docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc';"
docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc2';"
docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc3';"

echo -e "\033[0;33mVerifying topic asgard.public.customers-raw\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic asgard.public.customers-raw --from-beginning --max-messages 5


