#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

for component in producer consumer streams
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

exit 0

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

if [ ! -f ${DIR}/mysql-connector-java-5.1.45.jar ]
then
     log "Downloading mysql-connector-java-5.1.45.jar"
     wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.45/mysql-connector-java-5.1.45.jar
fi

# kafka-topics --bootstrap-server `grep "^\s*bootstrap.server" ${CONFIG_FILE} | tail -1` --command-config ${CONFIG_FILE} --topic customer-avro --create --replication-factor 3 --partitions 6

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.ccloud-demo.yml"

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

# FIXTHIS: https://github.com/vdesabou/kafka-docker-playground/issues/1457
# if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     create_topic mysql-application
     set -e
# fi

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
     docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic mysql-application --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 2'
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
          "connection.url": "http://elasticsearch:9200"
          }' \
     http://localhost:8083/connectors/elasticsearch-sink/config | jq .

sleep 40

if [ -z "$CLOUDFORMATION" ]
then
     log "Check that the data is available in Elasticsearch"
     curl -XGET 'http://localhost:9200/mysql-application/_search?pretty'
fi

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