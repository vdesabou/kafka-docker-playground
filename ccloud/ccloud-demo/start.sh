#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     echo "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

source ${DIR}/../../ccloud/ccloud-demo/Utils.sh

verify_installed "ccloud"
verify_installed "confluent"
verify_ccloud_login  "ccloud kafka cluster list"
verify_ccloud_details
check_if_continue

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

# kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" ${CONFIG_FILE} | tail -1` --command-config ${CONFIG_FILE} --topic customer-avro --create --replication-factor 3 --partitions 6

create_topic customer-avro

docker-compose down -v
docker-compose up -d
${DIR}/../../WaitForConnectAndControlCenter.sh

echo "-------------------------------------"
echo "Connector examples"
echo "-------------------------------------"

echo "Creating HttpSinkBasicAuth connector"
docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" connect \
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


sleep 20

echo "Confirm that the data was sent to the HTTP endpoint."
curl admin:password@localhost:9080/api/messages | jq .

create_topic mysql-application

echo "Creating MySQL source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "mysql-source",
               "config": {
                    "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
                    "tasks.max":"1",
                    "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
                    "table.whitelist":"application",
                    "mode":"timestamp+incrementing",
                    "timestamp.column.name":"last_modified",
                    "incrementing.column.name":"id",
                    "topic.prefix":"mysql-"
          }}' \
     http://localhost:8083/connectors | jq .

echo "Adding an element to the table"
docker exec mysql mysql --user=root --password=password --database=db -e "
INSERT INTO application (   \
  id,   \
  name, \
  team_email,   \
  last_modified \
) VALUES (  \
  2,    \
  'another',  \
  'another@apache.org',   \
  NOW() \
);"

echo "Verifying topic mysql-application"
# this command works for both cases
# docker-compose exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic mysql-application --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 2'
if [ "${SR_TYPE}" == "SCHEMA_REGISTRY_DOCKER" ]
then
     echo "INFO: Using Docker Schema Registry"
     # using https://github.com/confluentinc/examples/blob/5.3.1-post/clients/cloud/confluent-cli/confluent-cli-example.sh
     confluent local consume mysql-application -- --cloud --value-format avro --property schema.registry.url=http://127.0.0.1:8085 --from-beginning --max-messages 2
else
     echo "INFO: Using Confluent Cloud Schema Registry"
     # using https://github.com/confluentinc/examples/tree/5.3.1-post/clients/cloud/confluent-cli#example-2-avro-and-confluent-cloud-schema-registry
     confluent local consume mysql-application -- --cloud --value-format avro --property schema.registry.url=$SCHEMA_REGISTRY_URL --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --from-beginning --max-messages 2
fi



