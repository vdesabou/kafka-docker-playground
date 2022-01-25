#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-89390-filter-condition-smt-could-not-be-found.yml"


log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"

docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Creating JDBC PostgreSQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max": "1",
                    "connection.url": "jdbc:postgresql://postgres/postgres?user=myuser&password=mypassword&ssl=false",
                    "table.whitelist": "customers",
                    "mode": "timestamp+incrementing",
                    "timestamp.column.name": "update_ts",
                    "incrementing.column.name": "id",
                    "topic.prefix": "postgres-",
                    "validate.non.null":"false",
                    "errors.log.enable": "true",
                    "errors.log.include.messages": "true",
                    "transforms": "filterByGender",
                    "transforms.filterByGender.type": "org.apache.kafka.connect.transforms.Filter$Value",
                    "transforms.filterByGender.filter.condition": "$[?(@.gender == 'Female')]",
                    "transforms.filterByGender.filter.type": "include"
          }' \
     http://localhost:8083/connectors/postgres-source/config | jq .


# {
#   "error_code": 400,
#   "message": "Connector configuration is invalid and contains the following 2 error(s):\nInvalid value org.apache.kafka.connect.transforms.Filter$Value for configuration transforms.filterByGender.type: Class org.apache.kafka.connect.transforms.Filter$Value could not be found.\nInvalid value null for configuration transforms.filterByGender.type: Not a Transformation\nYou can also find the above list of errors at the endpoint `/connector-plugins/{connectorType}/config/validate`"
# }

sleep 5

log "Verifying topic postgres-customers"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic postgres-customers --from-beginning --max-messages 5


