#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

SERVICENOW_URL=${SERVICENOW_URL:-$1}
SERVICENOW_PASSWORD=${SERVICENOW_PASSWORD:-$2}

if [ -z "$SERVICENOW_URL" ]
then
     logerror "SERVICENOW_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$SERVICENOW_URL" != */ ]]
then
    logerror "SERVICENOW_URL does not end with "/" Example: https://dev12345.service-now.com/ "
    exit 1
fi

if [ -z "$SERVICENOW_PASSWORD" ]
then
     logerror "SERVICENOW_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -z "$CI" ]
then
     # this is github actions
     set +e
     log "Waking up servicenow instance..."
     docker run -e USERNAME="$SERVICENOW_DEVELOPER_USERNAME" -e PASSWORD="$SERVICENOW_DEVELOPER_PASSWORD" ruthless/servicenow-instance-wakeup:latest
     set -e
     log "sleeping 240 seconds"
     sleep 240
fi

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic test_table
set -e

log "Sending messages to topic test_table"
docker exec -i -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic test_table --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

log "Creating ServiceNow Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.servicenow.ServiceNowSinkConnector",
               "topics": "test_table",
               "servicenow.url": "'"$SERVICENOW_URL"'",
               "tasks.max": "1",
               "servicenow.table": "u_test_table",
               "servicenow.user": "admin",
               "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "key.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "key.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter" : "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
               "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "value.converter.basic.auth.credentials.source": "USER_INFO",
               "reporter.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "reporter.ssl.endpoint.identification.algorithm" : "https",
               "reporter.sasl.mechanism" : "PLAIN",
               "reporter.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "reporter.security.protocol" : "SASL_SSL",
               "reporter.admin.ssl.endpoint.identification.algorithm" : "https",
               "reporter.admin.sasl.mechanism" : "PLAIN",
               "reporter.admin.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "reporter.admin.security.protocol" : "SASL_SSL",
               "reporter.producer.ssl.endpoint.identification.algorithm" : "https",
               "reporter.producer.sasl.mechanism" : "PLAIN",
               "reporter.producer.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "reporter.producer.security.protocol" : "SASL_SSL",
               "reporter.error.topic.name": "test-error",
               "reporter.error.topic.replication.factor": 3,
               "reporter.error.topic.key.format": "string",
               "reporter.error.topic.value.format": "string",
               "reporter.result.topic.name": "test-result",
               "reporter.result.topic.key.format": "string",
               "reporter.result.topic.value.format": "string",
               "reporter.result.topic.replication.factor": 3,
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3"
          }' \
     http://localhost:8083/connectors/servicenow-sink/config | jq .


sleep 15

log "Confirm that the messages were delivered to the ServiceNow table"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
   curl -X GET \
    "${SERVICENOW_URL}/api/now/table/u_test_table" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' | jq .