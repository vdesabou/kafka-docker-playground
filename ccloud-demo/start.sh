#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
SR_TYPE=${1:-SCHEMA_REGISTRY_DOCKER} 
CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     echo "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi


echo "The following ccloud config is used:"
echo "---------------"
cat ${CONFIG_FILE}
echo "---------------"


if [ "${SR_TYPE}" == "SCHEMA_REGISTRY_DOCKER" ]
then
     echo "INFO: Using Docker Schema Registry"
     ./ccloud-generate-env-vars.sh schema_registry_docker.config
else 
     echo "INFO: Using Confluent Cloud Schema Registry"
     ./ccloud-generate-env-vars.sh ${CONFIG_FILE}
fi

if [ -f ./delta_configs/env.delta ]
then
     source ./delta_configs/env.delta
else
     echo "ERROR: delta_configs/env.delta has not been generated"
     exit 1
fi

set +e
echo "Create topic customer-avro in Confluent Cloud"
kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" ${CONFIG_FILE} | tail -1` --command-config ${CONFIG_FILE} --topic customer-avro --create --replication-factor 3 --partitions 6
set -e

${DIR}/../nosecurity/start.sh

echo "-------------------------------------"
echo "Running Basic Authentication Example"
echo "-------------------------------------"

echo "Creating HttpSinkBasicAuth connector"
docker-compose exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
          "name": "HttpSinkBasicAuth",
          "config": {
               "topics": "customer-avro",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.request.timeout.ms" : "20000",
               "confluent.topic.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
               "retry.backoff.ms" : "500",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "1",
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password"
          }}' \
     http://localhost:8083/connectors | jq .


sleep 10

echo "Confirm that the data was sent to the HTTP endpoint."
curl admin:password@localhost:9080/api/messages | jq .


