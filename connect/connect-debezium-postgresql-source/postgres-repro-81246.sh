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

# With all versions: "curr_amount":"x"

# With latest:  no Cannot parse column default value 'NULL::numeric' to type 'numeric'

# [2022-01-21 15:01:15,758] WARN [debezium-postgres-source3|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)
# [2022-01-21 15:01:15,758] WARN [debezium-postgres-source3|task-0] Cannot parse column default value 'CURRENT_TIMESTAMP' to type 'timestamp'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)


# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642777370275445},"update_ts":{"long":1642777370275445},"curr_amount":"x"}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642777406512,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513584\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513584},"xmin":null},"op":"r","ts_ms":{"long":1642777406516},"transaction":null}
# {"id":2}        {"before":null,"after":{"asgard.public.customers.Value":{"id":2,"first_name":{"string":"Ruthie"},"last_name":{"string":"Brockherst"},"email":{"string":"rbrockherst1@ow.ly"},"gender":{"string":"Female"},"club_status":{"string":"platinum"},"comments":{"string":"Reverse-engineered tangible interface"},"create_ts":{"long":1642777370276691},"update_ts":{"long":1642777370276691},"curr_amount":"x"}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642777406520,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513584\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513584},"xmin":null},"op":"r","ts_ms":{"long":1642777406521},"transaction":null}
# {"id":3}        {"before":null,"after":{"asgard.public.customers.Value":{"id":3,"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"email":{"string":"mcocci2@techcrunch.com"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Multi-tiered bandwidth-monitored capability"},"create_ts":{"long":1642777370277894},"update_ts":{"long":1642777370277894},"curr_amount":"x"}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642777406522,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513584\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513584},"xmin":null},"op":"r","ts_ms":{"long":1642777406522},"transaction":null}
# {"id":4}        {"before":null,"after":{"asgard.public.customers.Value":{"id":4,"first_name":{"string":"Hashim"},"last_name":{"string":"Rumke"},"email":{"string":"hrumke3@sohu.com"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Self-enabling 24/7 firmware"},"create_ts":{"long":1642777370278992},"update_ts":{"long":1642777370278992},"curr_amount":"x"}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642777406522,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513584\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513584},"xmin":null},"op":"r","ts_ms":{"long":1642777406522},"transaction":null}
# {"id":5}        {"before":null,"after":{"asgard.public.customers.Value":{"id":5,"first_name":{"string":"Hansiain"},"last_name":{"string":"Coda"},"email":{"string":"hcoda4@senate.gov"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Centralized full-range approach"},"create_ts":{"long":1642777370280235},"update_ts":{"long":1642777370280235},"curr_amount":"x"}},"source":{"version":"1.7.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642777406522,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513584\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513584},"xmin":null},"op":"r","ts_ms":{"long":1642777406522},"transaction":null}

# with 1.6.3
# [2022-01-21 15:01:15,758] WARN [debezium-postgres-source3|task-0] Cannot parse column default value 'NULL::numeric' to type 'numeric'. Expression evaluation is not supported. (io.debezium.connector.postgresql.connection.PostgresDefaultValueConverter:88)

# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642778381505293},"update_ts":{"long":1642778381505293},"curr_amount":"x"}},"source":{"version":"1.6.3.Final","connector":"postgresql","name":"asgard","ts_ms":1642778417657,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513520\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513520},"xmin":null},"op":"r","ts_ms":{"long":1642778417662},"transaction":null}
# {"id":2}        {"before":null,"after":{"asgard.public.customers.Value":{"id":2,"first_name":{"string":"Ruthie"},"last_name":{"string":"Brockherst"},"email":{"string":"rbrockherst1@ow.ly"},"gender":{"string":"Female"},"club_status":{"string":"platinum"},"comments":{"string":"Reverse-engineered tangible interface"},"create_ts":{"long":1642778381506442},"update_ts":{"long":1642778381506442},"curr_amount":"x"}},"source":{"version":"1.6.3.Final","connector":"postgresql","name":"asgard","ts_ms":1642778417668,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513520\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513520},"xmin":null},"op":"r","ts_ms":{"long":1642778417668},"transaction":null}
# {"id":3}        {"before":null,"after":{"asgard.public.customers.Value":{"id":3,"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"email":{"string":"mcocci2@techcrunch.com"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Multi-tiered bandwidth-monitored capability"},"create_ts":{"long":1642778381507422},"update_ts":{"long":1642778381507422},"curr_amount":"x"}},"source":{"version":"1.6.3.Final","connector":"postgresql","name":"asgard","ts_ms":1642778417669,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513520\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513520},"xmin":null},"op":"r","ts_ms":{"long":1642778417670},"transaction":null}
# {"id":4}        {"before":null,"after":{"asgard.public.customers.Value":{"id":4,"first_name":{"string":"Hashim"},"last_name":{"string":"Rumke"},"email":{"string":"hrumke3@sohu.com"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Self-enabling 24/7 firmware"},"create_ts":{"long":1642778381508668},"update_ts":{"long":1642778381508668},"curr_amount":"x"}},"source":{"version":"1.6.3.Final","connector":"postgresql","name":"asgard","ts_ms":1642778417670,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513520\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513520},"xmin":null},"op":"r","ts_ms":{"long":1642778417670},"transaction":null}
# {"id":5}        {"before":null,"after":{"asgard.public.customers.Value":{"id":5,"first_name":{"string":"Hansiain"},"last_name":{"string":"Coda"},"email":{"string":"hcoda4@senate.gov"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Centralized full-range approach"},"create_ts":{"long":1642778381509737},"update_ts":{"long":1642778381509737},"curr_amount":"x"}},"source":{"version":"1.6.3.Final","connector":"postgresql","name":"asgard","ts_ms":1642778417670,"snapshot":{"string":"true"},"db":"postgres","sequence":{"string":"[null,\"24513520\"]"},"schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24513520},"xmin":null},"op":"r","ts_ms":{"long":1642778417670},"transaction":null}


# With 1.4.1: no Cannot parse column default value at all

# {"id":1}        {"before":null,"after":{"asgard.public.customers.Value":{"id":1,"first_name":{"string":"Rica"},"last_name":{"string":"Blaisdell"},"email":{"string":"rblaisdell0@rambler.ru"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Universal optimal hierarchy"},"create_ts":{"long":1642779967424992},"update_ts":{"long":1642779967424992},"curr_amount":"x"}},"source":{"version":"1.4.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642780003344,"snapshot":{"string":"true"},"db":"postgres","schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24526088},"xmin":null},"op":"r","ts_ms":{"long":1642780003347},"transaction":null}
# {"id":2}        {"before":null,"after":{"asgard.public.customers.Value":{"id":2,"first_name":{"string":"Ruthie"},"last_name":{"string":"Brockherst"},"email":{"string":"rbrockherst1@ow.ly"},"gender":{"string":"Female"},"club_status":{"string":"platinum"},"comments":{"string":"Reverse-engineered tangible interface"},"create_ts":{"long":1642779967426284},"update_ts":{"long":1642779967426284},"curr_amount":"x"}},"source":{"version":"1.4.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642780003352,"snapshot":{"string":"true"},"db":"postgres","schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24526088},"xmin":null},"op":"r","ts_ms":{"long":1642780003352},"transaction":null}
# {"id":3}        {"before":null,"after":{"asgard.public.customers.Value":{"id":3,"first_name":{"string":"Mariejeanne"},"last_name":{"string":"Cocci"},"email":{"string":"mcocci2@techcrunch.com"},"gender":{"string":"Female"},"club_status":{"string":"bronze"},"comments":{"string":"Multi-tiered bandwidth-monitored capability"},"create_ts":{"long":1642779967427207},"update_ts":{"long":1642779967427207},"curr_amount":"x"}},"source":{"version":"1.4.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642780003354,"snapshot":{"string":"true"},"db":"postgres","schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24526088},"xmin":null},"op":"r","ts_ms":{"long":1642780003354},"transaction":null}
# {"id":4}        {"before":null,"after":{"asgard.public.customers.Value":{"id":4,"first_name":{"string":"Hashim"},"last_name":{"string":"Rumke"},"email":{"string":"hrumke3@sohu.com"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Self-enabling 24/7 firmware"},"create_ts":{"long":1642779967428251},"update_ts":{"long":1642779967428251},"curr_amount":"x"}},"source":{"version":"1.4.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642780003354,"snapshot":{"string":"true"},"db":"postgres","schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24526088},"xmin":null},"op":"r","ts_ms":{"long":1642780003354},"transaction":null}
# {"id":5}        {"before":null,"after":{"asgard.public.customers.Value":{"id":5,"first_name":{"string":"Hansiain"},"last_name":{"string":"Coda"},"email":{"string":"hcoda4@senate.gov"},"gender":{"string":"Male"},"club_status":{"string":"platinum"},"comments":{"string":"Centralized full-range approach"},"create_ts":{"long":1642779967429448},"update_ts":{"long":1642779967429448},"curr_amount":"x"}},"source":{"version":"1.4.1.Final","connector":"postgresql","name":"asgard","ts_ms":1642780003355,"snapshot":{"string":"true"},"db":"postgres","schema":"public","table":"customers","txId":{"long":580},"lsn":{"long":24526088},"xmin":null},"op":"r","ts_ms":{"long":1642780003355},"transaction":null}