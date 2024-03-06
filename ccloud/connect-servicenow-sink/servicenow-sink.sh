#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



function wait_for_end_of_hibernation () {
     MAX_WAIT=600
     CUR_WAIT=0
     set +e
     log "⌛ Waiting up to $MAX_WAIT seconds for end of hibernation to happen (it can take several minutes)"
     curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
     while [[ $(cat /tmp/out.txt) =~ "Sign in to the site to wake your instance" ]]
     do
          sleep 10
          curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs still show 'Sign in to the site to wake your instance' after $MAX_WAIT seconds.\n"
               exit 1
          fi
     done
     log "The instance is ready !"
     set -e
}

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

if [ ! -z "$GITHUB_RUN_NUMBER" ]
then
     # this is github actions
     set +e
     log "Waking up servicenow instance..."
     docker run -e USERNAME="$SERVICENOW_DEVELOPER_USERNAME" -e PASSWORD="$SERVICENOW_DEVELOPER_PASSWORD" vdesabou/servicenowinstancewakeup:latest
     set -e
     wait_for_end_of_hibernation
fi

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.yml"


#############

log "Creating topic in Confluent Cloud"
set +e
playground topic create --topic test_table
set -e

log "Sending messages to topic test_table"
playground topic produce -t test_table --nb-messages 3 << 'EOF'
{
  "fields": [
    {
      "name": "u_name",
      "type": "string"
    },
    {
      "name": "u_price",
      "type": "float"
    },
    {
      "name": "u_quantity",
      "type": "int"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Creating ServiceNow Sink connector"
playground connector create-or-update --connector servicenow-sink  << EOF
{
     "connector.class": "io.confluent.connect.servicenow.ServiceNowSinkConnector",
     "topics": "test_table",
     "servicenow.url": "$SERVICENOW_URL",
     "tasks.max": "1",
     "servicenow.table": "u_test_table",
     "servicenow.user": "admin",
     "servicenow.password": "$SERVICENOW_PASSWORD",
     "key.converter" : "io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url": "$SCHEMA_REGISTRY_URL",
     "key.converter.basic.auth.user.info": "\${file:/data:schema.registry.basic.auth.user.info}",
     "key.converter.basic.auth.credentials.source": "USER_INFO",
     "value.converter" : "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "$SCHEMA_REGISTRY_URL",
     "value.converter.basic.auth.user.info": "\${file:/data:schema.registry.basic.auth.user.info}",
     "value.converter.basic.auth.credentials.source": "USER_INFO",
     "reporter.bootstrap.servers": "\${file:/data:bootstrap.servers}",
     "reporter.admin.sasl.mechanism" : "PLAIN",
     "reporter.admin.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
     "reporter.admin.security.protocol" : "SASL_SSL",
     "reporter.producer.sasl.mechanism" : "PLAIN",
     "reporter.producer.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
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
     "confluent.topic.bootstrap.servers": "\${file:/data:bootstrap.servers}",
     "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
     "confluent.topic.security.protocol" : "SASL_SSL",
     "confluent.topic.replication.factor": "3"
}
EOF


sleep 15

log "Confirm that the messages were delivered to the ServiceNow table"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect \
   curl -X GET \
    "${SERVICENOW_URL}/api/now/table/u_test_table" \
    --user admin:"$SERVICENOW_PASSWORD" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "u_name" /tmp/result.log