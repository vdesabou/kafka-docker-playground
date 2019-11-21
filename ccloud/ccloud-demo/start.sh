#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     echo "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

source ${DIR}/../../ccloud/ccloud-demo/Utils.sh

verify_installed "mvn"
verify_installed "ccloud"
check_ccloud_version 0.192.0 || exit 1
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

# generate kafka-lag-exporter config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/kafka-lag-exporter/application.template.conf > ${DIR}/kafka-lag-exporter/application.conf

# kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" ${CONFIG_FILE} | tail -1` --command-config ${CONFIG_FILE} --topic customer-avro --create --replication-factor 3 --partitions 6

set +e
create_topic customer-avro
set -e

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

set +e
create_topic mysql-application
set -e

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

echo "Now we will test Service Account and ACLs"
check_if_continue

######################
## Service Account and ACLs
######################


##################################################
# Create a Service Account and API key and secret
# - A service account represents an application, and the service account name must be globally unique
##################################################

echo -e "\n# Create a new service account"
RANDOM_NUM=$((1 + RANDOM % 1000000))
SERVICE_NAME="demo-app-$RANDOM_NUM"
echo "ccloud service-account create $SERVICE_NAME --description $SERVICE_NAME"
ccloud service-account create $SERVICE_NAME --description $SERVICE_NAME || true
SERVICE_ACCOUNT_ID=$(ccloud service-account list | grep $SERVICE_NAME | awk '{print $1;}')

CLUSTER=$(ccloud prompt -f "%k")
echo -e "\n# Create an API key and secret for the new service account"
echo "ccloud api-key create --service-account-id $SERVICE_ACCOUNT_ID --resource $CLUSTER"
OUTPUT=$(ccloud api-key create --service-account-id $SERVICE_ACCOUNT_ID --resource $CLUSTER)
echo "$OUTPUT"
API_KEY_SA=$(echo "$OUTPUT" | grep '| API Key' | awk '{print $5;}')
API_SECRET_SA=$(echo "$OUTPUT" | grep '| Secret' | awk '{print $4;}')

echo -e "\n# Wait 90 seconds for the user and service account key and secret to propagate"
sleep 90

CLIENT_CONFIG="/tmp/client.config"
echo -e "\n# Create a local configuration file $CLIENT_CONFIG for the client to connect to Confluent Cloud with the newly created API key and secret"
echo "Write properties to $CLIENT_CONFIG:"
cat <<EOF > $CLIENT_CONFIG
ssl.endpoint.identification.algorithm=https
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
bootstrap.servers=${BOOTSTRAP_SERVERS}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username\="${API_KEY_SA}" password\="${API_SECRET_SA}";
EOF
cat $CLIENT_CONFIG

##################################################
# Run a Java client: before and after ACLs
#
# When ACLs are enabled on your Confluent Cloud cluster,
# by default no client applications are authorized.
#
# The following steps show the same Java producer failing at first due to
# 'TopicAuthorizationException' and then passing once the appropriate
# ACLs are configured
##################################################

POM=./producer-acl/pom.xml
TOPIC1="demo-topic-1"
set +e

echo -e "\n# By default, no ACLs are configured"
echo "ccloud kafka acl list --service-account-id $SERVICE_ACCOUNT_ID"
ccloud kafka acl list --service-account-id $SERVICE_ACCOUNT_ID

echo -e "\n# Run the Java producer to $TOPIC1: before ACLs"
mvn -q -f $POM clean package
if [[ $? != 0 ]]; then
  echo "ERROR: There seems to be a build failure error compiling the client code? Please troubleshoot"
  exit 1
fi
LOG1="/tmp/log.1"
java -jar ./producer-acl/target/producer-acl-1.0.0-jar-with-dependencies.jar $CLIENT_CONFIG $TOPIC1 > $LOG1 2>&1
echo "# Check logs for 'org.apache.kafka.common.errors.TopicAuthorizationException'"
OUTPUT=$(grep "org.apache.kafka.common.errors.TopicAuthorizationException" $LOG1)
if [[ ! -z $OUTPUT ]]; then
  echo "PASS: Producer failed due to org.apache.kafka.common.errors.TopicAuthorizationException (expected because there are no ACLs to allow this client application)"
else
  echo "FAIL: Something went wrong, check $LOG1"
fi

echo -e "\n# Create ACLs for the service account"
echo "ccloud kafka acl create --allow --service-account-id $SERVICE_ACCOUNT_ID --operation CREATE --topic $TOPIC1"
echo "ccloud kafka acl create --allow --service-account-id $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC1"
ccloud kafka acl create --allow --service-account-id $SERVICE_ACCOUNT_ID --operation CREATE --topic $TOPIC1
ccloud kafka acl create --allow --service-account-id $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC1
echo "ccloud kafka acl list --service-account-id $SERVICE_ACCOUNT_ID"
ccloud kafka acl list --service-account-id $SERVICE_ACCOUNT_ID
sleep 2

echo -e "\n# Run the Java producer to $TOPIC1: after ACLs"
LOG2="/tmp/log.2"
java -jar ./producer-acl/target/producer-acl-1.0.0-jar-with-dependencies.jar $CLIENT_CONFIG $TOPIC1 > $LOG2 2>&1
echo "# Check logs for '10 messages were produced to topic'"
OUTPUT=$(grep "10 messages were produced to topic" $LOG2)
if [[ ! -z $OUTPUT ]]; then
  echo "PASS: Producer works"
else
  echo "FAIL: Something went wrong, check $LOG2"
fi
cat $LOG2

##################################################
# Cleanup
# - Delete the ACLs, API key, service account
##################################################

echo -e "\n# Delete ACLs"
echo "ccloud kafka acl delete --allow --service-account-id $SERVICE_ACCOUNT_ID --operation CREATE --topic $TOPIC1"
echo "ccloud kafka acl delete --allow --service-account-id $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC1"
ccloud kafka acl delete --allow --service-account-id $SERVICE_ACCOUNT_ID --operation CREATE --topic $TOPIC1
ccloud kafka acl delete --allow --service-account-id $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC1

echo "ccloud service-account delete $SERVICE_ACCOUNT_ID"
ccloud service-account delete $SERVICE_ACCOUNT_ID

echo "ccloud api-key delete $API_KEY_SA"
ccloud api-key delete $API_KEY_SA 1>/dev/null

# kafka-consumer-groups command for Confluent Cloud
# https://support.confluent.io/hc/en-us/articles/360022562212-kafka-consumer-groups-command-for-Confluent-Cloud
if [[ ! $(type kafka-consumer-groups 2>&1) =~ "not found" ]]; then
     echo "Example showing how to use kafka-consumer-groups command for Confluent Cloud"
     kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config $CONFIG_FILE --list
     kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config $CONFIG_FILE --group simple-stream --describe
fi
