#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

if [ -z "$CI" ] && [ -z "$CLOUDFORMATION" ]
then
     # not running with CI
     verify_installed "ccloud"
     check_ccloud_version 1.7.0 || exit 1
     verify_ccloud_login  "ccloud kafka cluster list"
     verify_ccloud_details
     check_if_continue
fi

SR_TYPE=${1:-SCHEMA_REGISTRY_DOCKER}
CONFIG_FILE=~/.ccloud/config

if [ ! -f ${CONFIG_FILE} ]
then
     logerror "ERROR: ${CONFIG_FILE} is not set"
     exit 1
fi

if [ "${SR_TYPE}" == "SCHEMA_REGISTRY_DOCKER" ]
then
     log "INFO: Using Docker Schema Registry"
     ./ccloud-generate-env-vars.sh schema_registry_docker.config
else
     log "INFO: Using Confluent Cloud Schema Registry"
     ./ccloud-generate-env-vars.sh ${CONFIG_FILE}
fi

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

for component in producer consumer streams producer-acl
do
     if [ ! -f ${DIR}/${component}/target/${component}-1.0.0-jar-with-dependencies.jar ]
     then
          log "Building jar for ${component}"
          docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
     fi
done

if [ ! -z "$CI" ] || [ ! -z "$CLOUDFORMATION" ]
then
     # running with github actions or cloudformation
     log "Installing ccloud CLI"
     curl -L --http1.1 https://cnfl.io/ccloud-cli | sudo sh -s -- -b /usr/local/bin
     export PATH=$PATH:/usr/local/bin
     log "##################################################"
     log "Log in to Confluent Cloud"
     log "##################################################"
     ccloud login --save
     log "Use environment $ENVIRONMENT"
     ccloud environment use $ENVIRONMENT
     log "Use cluster $CLUSTER_LKC"
     ccloud kafka cluster use $CLUSTER_LKC
     log "Store api key $CLOUD_KEY"
     ccloud api-key store $CLOUD_KEY $CLOUD_SECRET --resource $CLUSTER_LKC --force
     log "Use api key $CLOUD_KEY"
     ccloud api-key use $CLOUD_KEY --resource $CLUSTER_LKC
fi

# required for dabz/ccloudexporter
export CCLOUD_CLUSTER=$(ccloud prompt -f "%k")

# generate config.yml
sed -e "s|:CCLOUD_CLUSTER:|$CCLOUD_CLUSTER|g" \
    ${DIR}/config-template.yml > ${DIR}/config.yml

log "Create API key and secret with cloud resource for Metrics API"
log "ccloud api-key create --resource cloud"
OUTPUT=$(ccloud api-key create --resource cloud)
export API_KEY_CLOUD=$(echo "$OUTPUT" | grep '| API Key' | awk '{print $5;}')
export API_SECRET_CLOUD=$(echo "$OUTPUT" | grep '| Secret' | awk '{print $4;}')

echo "$API_KEY_CLOUD" > api_key_cloud_to_delete

# generate librdkafka.config config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/client-dotnet/librdkafka.config.template > ${DIR}/client-dotnet/librdkafka.config

# generate kafka-lag-exporter config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/kafka-lag-exporter/application.template.conf > ${DIR}/kafka-lag-exporter/application.conf

# generate data file for externalizing secrets
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/data.template > ${DIR}/data

# kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" ${CONFIG_FILE} | tail -1` --command-config ${CONFIG_FILE} --topic customer-avro --create --replication-factor 3 --partitions 6

set +e
log "Cleanup connect worker topics"
delete_topic connect-status-demo-${TAG}
delete_topic connect-offsets-demo-${TAG}
delete_topic connect-configs-demo-${TAG}
set -e

docker-compose build
docker-compose down -v --remove-orphans
docker-compose up -d
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh

log "-------------------------------------"
log "Dotnet client examples"
log "-------------------------------------"
set +e
create_topic topic-dotnet
set -e

log "Starting dotnet producer"
docker exec -d client-dotnet dotnet CCloud.dll produce topic-dotnet /tmp/librdkafka.config

log "Starting dotnet consume"
docker exec -d client-dotnet dotnet CCloud.dll consume topic-dotnet /tmp/librdkafka.config

log "-------------------------------------"
log "Connector examples"
log "-------------------------------------"

set +e
create_topic mysql-application
set -e

log "Creating MySQL source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
               "tasks.max":"1",
               "connection.url":"jdbc:mysql://mysql:3306/db?user=user&password=password&useSSL=false",
               "table.whitelist":"application",
               "mode":"timestamp+incrementing",
               "timestamp.column.name":"last_modified",
               "incrementing.column.name":"id",
               "topic.prefix":"mysql-"
          }' \
     http://localhost:8083/connectors/mysql-source/config | jq .

log "Adding an element to the table"
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


# # with avro
# confluent local consume customer-avro -- --cloud --value-format avro --property schema.registry.url=http://127.0.0.1:8085 --from-beginning

# # without avro
# confluent local consume kriscompact -- --cloud --from-beginning

# # with avro
# kafka-avro-console-consumer --topic customer-avro --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 2

# # without avro
# kafka-console-consumer --topic kriscompact --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --from-beginning --max-messages 2

sleep 30

if [ -z "$CI" ] && [ -z "$CLOUDFORMATION" ]
then
     # not running with CI
     log "Verifying topic mysql-application"
     # this command works for both cases (with local schema registry and Confluent Cloud Schema Registry)
     docker-compose exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic mysql-application --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 2'
fi

# Example using confluent CLI:
# if [ "${SR_TYPE}" == "SCHEMA_REGISTRY_DOCKER" ]
# then
#      log "INFO: Using Docker Schema Registry"
#      # using https://github.com/confluentinc/examples/blob/5.3.2-post/clients/cloud/confluent-cli/confluent-cli-example.sh
#      confluent local consume mysql-application -- --cloud --value-format avro --property schema.registry.url=http://127.0.0.1:8085 --from-beginning --max-messages 2
# else
#      log "INFO: Using Confluent Cloud Schema Registry"
#      # using https://github.com/confluentinc/examples/tree/5.3.2-post/clients/cloud/confluent-cli#example-2-avro-and-confluent-cloud-schema-registry
#      confluent local consume mysql-application -- --cloud --value-format avro --property schema.registry.url=$SCHEMA_REGISTRY_URL --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --from-beginning --max-messages 2
# fi

log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "topics": "mysql-application",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.request.timeout.ms" : "20000",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3",
               "reporter.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "reporter.admin.sasl.mechanism" : "PLAIN",
               "reporter.admin.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "reporter.admin.security.protocol" : "SASL_SSL",
               "reporter.producer.sasl.mechanism" : "PLAIN",
               "reporter.producer.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "reporter.producer.security.protocol" : "SASL_SSL",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 3,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 3,
               "retry.backoff.ms" : "500",
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .

sleep 30

if [ -z "$CLOUDFORMATION" ]
then
     log "Confirm that the data was sent to the HTTP endpoint."
     curl admin:password@localhost:9083/api/messages | jq .
fi

log "Creating Elasticsearch Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
        "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
          "tasks.max": "1",
          "topics": "mysql-application",
          "key.ignore": "true",
          "connection.url": "http://elasticsearch:9200",
          "type.name": "kafka-connect",
          "name": "elasticsearch-sink"
          }' \
     http://localhost:8083/connectors/elasticsearch-sink/config | jq .

sleep 40

if [ -z "$CLOUDFORMATION" ]
then
     log "Check that the data is available in Elasticsearch"
     curl -XGET 'http://localhost:9200/mysql-application/_search?pretty'
fi
if [ -z "$CLOUDFORMATION" ]
then
     exit 0
fi
log "Now we will test Service Account and ACLs"
check_if_continue

######################
## Service Account and ACLs
######################

##################################################
# Create a Service Account and API key and secret
# - A service account represents an application, and the service account name must be globally unique
##################################################

log "Create a new service account"
RANDOM_NUM=$((1 + RANDOM % 1000000))
SERVICE_NAME="my-java-producer-app-$RANDOM_NUM"
log "ccloud service-account create $SERVICE_NAME --description $SERVICE_NAME"
ccloud service-account create $SERVICE_NAME --description $SERVICE_NAME || true
SERVICE_ACCOUNT_ID=$(ccloud service-account list | grep $SERVICE_NAME | awk '{print $1;}')

CCLOUD_CLUSTER=$(ccloud prompt -f "%k")
log "Create an API key and secret for the new service account"
log "ccloud api-key create --service-account $SERVICE_ACCOUNT_ID --resource $CCLOUD_CLUSTER"
OUTPUT=$(ccloud api-key create --service-account $SERVICE_ACCOUNT_ID --resource $CCLOUD_CLUSTER)
API_KEY_SA=$(echo "$OUTPUT" | grep '| API Key' | awk '{print $5;}')
API_SECRET_SA=$(echo "$OUTPUT" | grep '| Secret' | awk '{print $4;}')

log "Wait 90 seconds for the user and service account key and secret to propagate"
sleep 90

CLIENT_CONFIG="/tmp/client.config"
log "Create a local configuration file $CLIENT_CONFIG for the client to connect to Confluent Cloud with the newly created API key and secret"
log "Write properties to $CLIENT_CONFIG:"
cat <<EOF > $CLIENT_CONFIG
ssl.endpoint.identification.algorithm=https
sasl.mechanism=PLAIN
security.protocol=SASL_SSL
bootstrap.servers=${BOOTSTRAP_SERVERS}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username\="${API_KEY_SA}" password\="${API_SECRET_SA}";
EOF

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

TOPIC_ACL="demo-acl-topic"
set +e
create_topic $TOPIC_ACL

log "By default, no ACLs are configured"
log "ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID"
ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID

log "Run the Java producer to $TOPIC_ACL: before ACLs"
LOG1="/tmp/log.1"
docker cp $CLIENT_CONFIG producer-acl:/tmp/
docker exec producer-acl bash -c "java -jar producer-acl-1.0.0-jar-with-dependencies.jar $CLIENT_CONFIG $TOPIC_ACL" > $LOG1 2>&1
log "# Check logs for 'org.apache.kafka.common.errors.TopicAuthorizationException'"
OUTPUT=$(grep "org.apache.kafka.common.errors.TopicAuthorizationException" $LOG1)
if [[ ! -z $OUTPUT ]]; then
  log "PASS: Producer failed due to org.apache.kafka.common.errors.TopicAuthorizationException (expected because there are no ACLs to allow this client application)"
else
  logerror "FAIL: Something went wrong, check $LOG1"
fi

log "Create ACLs for the service account"
log "ccloud kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL"
ccloud kafka acl create --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL
log "ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID"
ccloud kafka acl list --service-account $SERVICE_ACCOUNT_ID

sleep 20

log "Run the Java producer to $TOPIC_ACL: after ACLs"
LOG2="/tmp/log.2"
docker exec producer-acl bash -c "java -jar producer-acl-1.0.0-jar-with-dependencies.jar $CLIENT_CONFIG $TOPIC_ACL" > $LOG2 2>&1
log "# Check logs for '10 messages were produced to topic'"
OUTPUT=$(grep "10 messages were produced to topic" $LOG2)
if [[ ! -z $OUTPUT ]]; then
  log "PASS: Producer works"
else
  logerror "FAIL: Something went wrong, check $LOG2"
fi
cat $LOG2

##################################################
# Cleanup
# - Delete the ACLs, API key, service account
##################################################

log "Delete ACLs"
log "ccloud kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL"
ccloud kafka acl delete --allow --service-account $SERVICE_ACCOUNT_ID --operation WRITE --topic $TOPIC_ACL

log "ccloud service-account delete $SERVICE_ACCOUNT_ID"
ccloud service-account delete $SERVICE_ACCOUNT_ID

log "ccloud api-key delete $API_KEY_SA"
ccloud api-key delete $API_KEY_SA 1>/dev/null

# kafka-consumer-groups command for Confluent Cloud
# https://support.confluent.io/hc/en-us/articles/360022562212-kafka-consumer-groups-command-for-Confluent-Cloud
if [[ ! $(type kafka-consumer-groups 2>&1) =~ "not found" ]]; then
     log "Example showing how to use kafka-consumer-groups command for Confluent Cloud"
     kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config $CONFIG_FILE --list
     kafka-consumer-groups --bootstrap-server $BOOTSTRAP_SERVERS --command-config $CONFIG_FILE --group simple-stream --describe
fi

if [ ! -z "$CI" ]
then
     # running with github actions
     log "##################################################"
     log "Stopping everything"
     log "##################################################"
     bash ${DIR}/stop.sh
fi