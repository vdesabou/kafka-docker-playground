#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#############
${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose-connect-onprem-to-cloud.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic create --topic products-avro
set -e

log "Sending messages to topic products-avro on source OnPREM cluster"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic products-avro --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"name","type":"string"},
{"name":"price", "type": "float"}, {"name":"quantity", "type": "int"}]}' << EOF
{"name": "scissors", "price": 2.75, "quantity": 3}
{"name": "tape", "price": 0.99, "quantity": 10}
{"name": "notebooks", "price": 1.99, "quantity": 5}
EOF

playground connector create-or-update --connector replicate-onprem-to-cloud << EOF
{
     "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
     "src.consumer.group.id": "replicate-onprem-to-cloud",
     "src.value.converter": "io.confluent.connect.avro.AvroConverter",
     "src.value.converter.schema.registry.url": "http://schema-registry:8081",
     "src.kafka.bootstrap.servers": "broker:9092",

     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "$SCHEMA_REGISTRY_URL",
     "value.converter.basic.auth.user.info": "\${file:/data:schema.registry.basic.auth.user.info}",
     "value.converter.basic.auth.credentials.source": "USER_INFO",

     "dest.kafka.ssl.endpoint.identification.algorithm":"https",
     "dest.kafka.bootstrap.servers": "\${file:/data:bootstrap.servers}",
     "dest.kafka.security.protocol" : "SASL_SSL",
     "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
     "dest.kafka.sasl.mechanism":"PLAIN",
     "dest.kafka.request.timeout.ms":"20000",
     "dest.kafka.retry.backoff.ms":"500",
     "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
     "confluent.topic.sasl.mechanism" : "PLAIN",
     "confluent.topic.bootstrap.servers": "\${file:/data:bootstrap.servers}",
     "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
     "confluent.topic.security.protocol" : "SASL_SSL",
     "confluent.topic.replication.factor": "3",
     "provenance.header.enable": true,
     "topic.whitelist": "products-avro",
     "topic.config.sync": false,
     "topic.auto.create": false
}
EOF

# In order to remove avro converter metadata added in schema, we can set:
# "value.converter.connect.meta.data": false

log "Verify we have received the data in products-avro topic"
timeout 60 docker container exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect bash -c 'kafka-avro-console-consumer --topic products-avro --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --max-messages 3'