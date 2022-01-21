#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-81246.yml"


log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"
docker exec postgres psql -U myuser -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments, curr_amount) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management', 1.4);"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U myuser -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Creating Debezium PostgreSQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
                    "tasks.max": "1",
                    "database.hostname": "postgres",
                    "database.port": "5432",
                    "database.user": "myuser",
                    "database.password": "mypassword",
                    "database.dbname" : "postgres",
                    "database.server.name": "asgard",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "transforms": "addTopicSuffix",
                    "transforms.addTopicSuffix.type":"org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.addTopicSuffix.regex":"(.*)",
                    "transforms.addTopicSuffix.replacement":"$1-raw"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .



sleep 5

log "Verifying topic asgard.public.customers-raw"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic asgard.public.customers-raw --from-beginning --property print.key=true --max-messages 5

# With latest (1.7.1):  no Cannot parse column default value 'NULL::numeric' to type 'numeric', but "curr_amount":"x"

# [2022-01-21 15:01:15,758] WARN [debezium-postgres-source3|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)
# [2022-01-21 15:01:15,758] WARN [debezium-postgres-source3|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)


# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642781028730102},"update_ts":{"long":1642781028730102},"curr_amount":"x"}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642781065106,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24514616\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24514616},"xmin":null},"op":"r","ts_ms":{"long":1642781065111},"transaction":null}

# with 1.6.3 -> "curr_amount":"x"
# [2022-01-21 16:01:53,106] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)
# [2022-01-21 16:01:53,107] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)
# [2022-01-21 16:01:53,107] WARN [debezium-postgres-source|task-0] Cannot parse column default value 'NULL::numeric' to type 'numeric'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)

# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642780876781560},"update_ts":{"long":1642780876781560},"curr_amount":"x"}},"source":{"version":"1.6.3.Final","connector":"postgresql","name":"asgard","ts_ms":1642780913015,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24524632\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24524632},"xmin":null},"op":"r","ts_ms":{"long":1642780913018},"transaction":null}

# With 1.4.1: no Cannot parse column default value at all and "curr_amount":"1.2"

# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642780714611751},"update_ts":{"long":1642780714611751},"curr_amount":1.2}},"source":{"version":"1.4.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642780750771,"snapshot":{"string":"true"},"db":"postgres","schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24530848},"xmin":null},"op":"r","ts_ms":{"long":1642780750774},"transaction":null}