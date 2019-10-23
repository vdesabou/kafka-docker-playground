#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Show content of CUSTOMERS table:"
docker container exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo "Adding an element to the table"

docker container exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

echo "Show content of CUSTOMERS table:"
docker container exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

echo "Creating JDBC PostgreSQL source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "postgres-source",
               "config": {
                    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=postgres&password=postgres&ssl=false",
                    "table.whitelist": "customers",
                    "mode": "timestamp+incrementing",
                    "timestamp.column.name": "update_ts",
                    "incrementing.column.name": "id",
                    "topic.prefix": "postgres-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true"
          }}' \
     http://localhost:8083/connectors | jq .


sleep 5

echo "Verifying topic postgres-customers"
docker container exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic postgres-customers --from-beginning --max-messages 5


