#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-repro-debezium.yml"

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
delete_topic asgard_public_customers
sleep 5
create_topic asgard_public_customers
set -e

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Adding an element to the table"

docker exec postgres psql -U postgres -d postgres -c "insert into customers (id, first_name, last_name, email, gender, comments) values (21, 'Bernardo', 'Dudman', 'bdudmanb@lulu.com', 'Male', 'Robust bandwidth-monitored budgetary management');"

log "Show content of CUSTOMERS table:"
docker exec postgres bash -c "psql -U postgres -d postgres -c 'SELECT * FROM CUSTOMERS'"

log "Creating Debezium MongoDB source connector"

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
                    "key.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
                    "key.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
                    "key.converter.basic.auth.credentials.source": "USER_INFO",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
                    "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
                    "value.converter.basic.auth.credentials.source": "USER_INFO",
                    "transforms": "RemoveDots,ExtractField",
                    "transforms.RemoveDots.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.RemoveDots.regex": "(.*)\\.(.*)\\.(.*)",
                    "transforms.RemoveDots.replacement": "$1_$2_$3",
                    "transforms.ExtractField.type":"org.apache.kafka.connect.transforms.ExtractField$Key",
                    "transforms.ExtractField.field":"id"
          }' \
     http://localhost:8083/connectors/debezium-postgres-source/config | jq .

sleep 5


log "Verifying topic asgard_public_customers"
docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic asgard_public_customers --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning  --property print.key=true --max-messages 1'

log "Creating GCP Firebase Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.firebase.FirebaseSinkConnector",
                    "tasks.max" : "1",
                    "topics":"asgard_public_customers",
                    "gcp.firebase.credentials.path": "/tmp/keyfile.json",
                    "gcp.firebase.database.reference": "https://'"$PROJECT"'.firebaseio.com/musicBlog",
                    "insert.mode":"update",
                    "key.converter" : "io.confluent.connect.avro.AvroConverter",
                    "key.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
                    "key.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
                    "key.converter.basic.auth.credentials.source": "USER_INFO",
                    "value.converter" : "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
                    "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
                    "value.converter.basic.auth.credentials.source": "USER_INFO",
                    "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
                    "confluent.topic.sasl.mechanism" : "PLAIN",
                    "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
                    "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.replication.factor": "3"
          }' \
     http://localhost:8083/connectors/firebase-sink/config | jq .

log "Follow README to verify data is in Firebase"
