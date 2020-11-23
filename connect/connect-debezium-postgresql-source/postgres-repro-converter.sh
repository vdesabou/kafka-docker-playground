#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/AccessPermissionLocation/target/AccessPermissionLocation-1.0.0-SNAPSHOT.jar ]
then
     # build AccessPermissionLocation transform
     log "Build AccessPermissionLocation transform"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/AccessPermissionLocation":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/AccessPermissionLocation/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext-repro-converter.yml"


log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"

docker exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Creating Debezium PostgreSQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                    "tasks.max": "1",
                    "database.hostname": "postgres",
                    "database.port": "5432",
                    "database.user": "postgres",
                    "database.password": "postgres",
                    "database.dbname" : "postgres",
                    "database.server.name": "asgard",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "converters": "accessPermissionLocation",
                    "accessPermissionLocation.type": "com.github.vdesabou.kafka.connect.transforms.AccessPermissionLocation",
                    "accessPermissionLocation.schema.name": "io.debezium.postgresql.type.UUID",
                    "transforms": "addTopicSuffix",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .



sleep 5

log "Verifying topic asgard.public.customers-raw"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --max-messages 5


