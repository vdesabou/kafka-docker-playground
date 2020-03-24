#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-repro-avro-proxy.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

#############
if [ -f ${DIR}/env.source ]
then
     source ${DIR}/env.source
else
     logerror "ERROR: ${DIR}/env.source does not exist, create it with following config parameters"

     logerror 'BOOTSTRAP_SERVERS_SRC="pkc-l6wr6.europe-west2.gcp.confluent.cloud:9092"'
     logerror 'CLOUD_KEY_SRC="xxx"'
     logerror 'CLOUD_SECRET_SRC="xxx"'
     logerror 'SASL_JAAS_CONFIG_SRC="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$CLOUD_KEY_SRC\" password=\"$CLOUD_SECRET_SRC\";"'
     logerror 'SCHEMA_REGISTRY_URL_SRC="https://xxx.confluent.cloud"'
     logerror 'SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="xxxx:xxxx"'

     exit 1
fi
#############

# log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
# set +e
# create_topic topic-replicator-avro
# set -e

log "Sending messages to topic topic-replicator-avro on SRC cluster (topic topic-replicator-avro should be created manually first)"
docker exec -i -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e SASL_JAAS_CONFIG_SRC="$SASL_JAAS_CONFIG_SRC" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC" -e SCHEMA_REGISTRY_URL_SRC="$SCHEMA_REGISTRY_URL_SRC" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS_SRC --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG_SRC" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC" --property schema.registry.url=$SCHEMA_REGISTRY_URL_SRC --topic topic-replicator-avro --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF

docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e CLOUD_KEY="$CLOUD_KEY" -e CLOUD_SECRET="$CLOUD_SECRET" -e BOOTSTRAP_SERVERS_SRC="$BOOTSTRAP_SERVERS_SRC" -e CLOUD_KEY_SRC="$CLOUD_KEY_SRC" -e CLOUD_SECRET_SRC="$CLOUD_SECRET_SRC" -e SCHEMA_REGISTRY_URL_SRC="$SCHEMA_REGISTRY_URL_SRC" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "src.consumer.group.id": "replicate-demo-to-travis",
    "src.value.converter": "io.confluent.connect.avro.AvroConverter",
    "src.value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL_SRC"'",
    "src.value.converter.basic.auth.user.info": "'"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC"'",
    "src.value.converter.basic.auth.credentials.source": "USER_INFO",

          "src.kafka.ssl.endpoint.identification.algorithm":"https",
          "src.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS_SRC"'",
          "src.kafka.security.protocol" : "SASL_SSL",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY_SRC'\" password=\"'$CLOUD_SECRET_SRC'\";",
          "src.kafka.sasl.mechanism":"PLAIN",
          "src.kafka.request.timeout.ms":"20000",
          "src.kafka.retry.backoff.ms":"500",

          "src.value.converter.proxy.host": "haproxy",
          "src.value.converter.proxy.port": "8080",

    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "'"$SCHEMA_REGISTRY_URL"'",
    "value.converter.basic.auth.user.info": "'"$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO"'",
    "value.converter.basic.auth.credentials.source": "USER_INFO",


          "dest.kafka.ssl.endpoint.identification.algorithm":"https",
          "dest.kafka.bootstrap.servers": "'"$BOOTSTRAP_SERVERS"'",
          "dest.kafka.security.protocol" : "SASL_SSL",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY'\" password=\"'$CLOUD_SECRET'\";",
          "dest.kafka.sasl.mechanism":"PLAIN",
          "dest.kafka.request.timeout.ms":"20000",
          "dest.kafka.retry.backoff.ms":"500",
          "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
          "confluent.topic.sasl.mechanism" : "PLAIN",
          "confluent.topic.bootstrap.servers": "'"$BOOTSTRAP_SERVERS_SRC"'",
          "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"'$CLOUD_KEY_SRC'\" password=\"'$CLOUD_SECRET_SRC'\";",
          "confluent.topic.security.protocol" : "SASL_SSL",
          "confluent.topic.replication.factor": "3",
          "provenance.header.enable": true,
          "topic.whitelist": "topic-replicator-avro"
          }' \
     http://localhost:8083/connectors/replicate-demo-to-travis/config | jq .


# curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC https://psrc-lgkvv.europe-west3.gcp.confluent.cloud/subjects
# curl -u $SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO_SRC http://localhost:8080/subjects

log "Verify we have received the data in topic-replicator-avro topic"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e BASIC_AUTH_CREDENTIALS_SOURCE="$BASIC_AUTH_CREDENTIALS_SOURCE" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic topic-replicator-avro --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=$BASIC_AUTH_CREDENTIALS_SOURCE --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 3'