#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f ${DIR}/producer-onprem/target/producer-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer-onprem"
     docker run -it --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer-onprem":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer-onprem/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

if [ ! -f ${DIR}/producer-cloud/target/producer-1.0.0-jar-with-dependencies.jar ]
then
     log "Building jar for producer-cloud"
     docker run -it --rm -e TAG=$TAG_BASE -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -v "${DIR}/producer-cloud":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/producer-cloud/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn package
fi

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-executable-onprem-to-cloud-topicrecordnamestrategy.yml" -a -b

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

# generate executable-onprem-to-cloud-producer-repro-avro.properties config
sed -e "s|:BOOTSTRAP_SERVERS:|$BOOTSTRAP_SERVERS|g" \
    -e "s|:CLOUD_KEY:|$CLOUD_KEY|g" \
    -e "s|:CLOUD_SECRET:|$CLOUD_SECRET|g" \
    ${DIR}/executable-onprem-to-cloud-producer-repro-avro.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-producer-repro-avro.properties

# generate executable-onprem-to-cloud-replicator-repro-avro-topicrecordnamestrategy.properties config
sed -e "s|:SCHEMA_REGISTRY_URL:|$SCHEMA_REGISTRY_URL|g" \
    -e "s|:SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO:|$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO|g" \
    ${DIR}/executable-onprem-to-cloud-replicator-repro-avro-topicrecordnamestrategy.properties > ${DIR}/tmp
mv ${DIR}/tmp ${DIR}/executable-onprem-to-cloud-replicator-repro-avro-topicrecordnamestrategy.properties

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
delete_topic executable-products-avro
sleep 3
create_topic executable-products-avro
delete_topic connect-onprem-to-cloud-avro.offsets
delete_topic connect-onprem-to-cloud-avro.status
delete_topic connect-onprem-to-cloud-avro.config
set -e

log "Delete schema for topic"
set +e
ccloud schema-registry schema delete --subject executable-products-avro-com.github.vdesabou.Customer --version latest
set -e

# Avoid java.lang.OutOfMemoryError: Java heap space
docker container restart connect
sleep 5

log "Run the Java producer-onprem, it sends one request every 5 seconds and use TopicRecordNameStrategy. Logs are in producer-onprem.log."
docker exec producer-onprem bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer-onprem.log 2>&1 &


log "Run the Java producer-cloud, it sends one request every 5 seconds and use TopicRecordNameStrategy. Logs are in producer-cloud.log."
docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" producer-cloud bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar" > producer-cloud.log 2>&1 &

sleep 15

log "Starting replicator executable (logs are in /tmp/replicator.log):"
# run in detach mode -d
docker exec -d connect bash -c 'export CLASSPATH=/etc/kafka-connect/jars/replicator-rest-extension-*.jar; replicator --consumer.config /etc/kafka/executable-onprem-to-cloud-consumer-repro-avro.properties --producer.config /etc/kafka/executable-onprem-to-cloud-producer-repro-avro.properties  --replication.config /etc/kafka/executable-onprem-to-cloud-replicator-repro-avro.properties  --cluster.id executable-onprem-to-cloud --whitelist executable-products-avro > /tmp/replicator.log 2>&1'

# docker exec connect bash -c 'export CLASSPATH=/etc/kafka-connect/jars/replicator-rest-extension-*.jar; replicator --consumer.config /etc/kafka/executable-onprem-to-cloud-consumer-repro-avro.properties --producer.config /etc/kafka/executable-onprem-to-cloud-producer-repro-avro.properties  --replication.config /etc/kafka/executable-onprem-to-cloud-replicator-repro-avro.properties  --cluster.id executable-onprem-to-cloud --whitelist executable-products-avro'

sleep 50
log "Verify we have received the data in executable-products-avro topic"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic executable-products-avro --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 3'

log "Copying replicator logs to /tmp/replicator.log"
docker cp connect:/tmp/replicator.log /tmp/replicator.log
