#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext-wal2json-noissue.yml"

#################
# This test is using debezium/postgres:10
# which is using wal2json dated from 11 Dec 2018 (including fix for https://issues.jboss.org/browse/DBZ-842 / https://github.com/eulerto/wal2json/issues/74)
#################
    # using this image we get no issue

echo "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo "Adding an element to the table"

docker exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

echo "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo "Creating Debezium PostgreSQL source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "debezium-postgres-source",
               "config": {
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
          }}' \
     http://localhost:8083/connectors | jq .



sleep 5

echo "Updating elements to the table"

docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc';"
docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc2';"
docker exec postgres psql -U postgres -d postgres -c "update customers set first_name = 'vinc3';"

echo "Verifying topic asgard.public.customers-raw"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic asgard.public.customers-raw --from-beginning --max-messages 5


