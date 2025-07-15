#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

JAAS_CONFIG_FILE="/tmp/jaas_config.file"
if version_gt $TAG_BASE "7.9.9"; then
  export JAAS_CONFIG_FILE="/tmp/jaas_config_8_plus.file"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p read -o SUBJECT_READ
docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p write -o SUBJECT_WRITE

# ccloud/schema-registry-security-plugin failing with 5.5.3 #223
# GLOBAL_SUBJECTS_READ replaced by GLOBAL_READ in CP 6.1.0 and onward
operations_list="SUBJECT_READ:SUBJECT_WRITE:SUBJECT_DELETE:SUBJECT_COMPATIBILITY_READ:SUBJECT_COMPATIBILITY_WRITE:GLOBAL_COMPATIBILITY_WRITE:GLOBAL_SUBJECTS_READ"
if version_gt $TAG_BASE "6.0.99"; then
     operations_list="SUBJECT_READ:SUBJECT_WRITE:SUBJECT_DELETE:SUBJECT_COMPATIBILITY_READ:SUBJECT_COMPATIBILITY_WRITE:GLOBAL_COMPATIBILITY_WRITE:GLOBAL_READ"
fi
docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --add -s '*' -p admin -o $operations_list

docker exec schema-registry sr-acl-cli --config /etc/schema-registry/schema-registry.properties --list

log "Schema Registry is listening on http://localhost:8081"
log "-> user:password  |  description"
log "-> _____________"
log "-> read:read    |  Global read access (SUBJECT_READ)"
log "-> write:write  |  Global write access (SUBJECT_WRITE)"
log "-> admin:admin  |  Global admin access (All operations, i.e $operations_list)"

log "Create a topic"
docker exec broker kafka-topics --create --topic my-topic --bootstrap-server broker:9092 --replication-factor 1 --partitions 1

log "Registering a subject with write user"
curl -X POST -u write:write http://localhost:8081/subjects/my-topic-value/versions \
  --header 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '
{
    "schema": "{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"u_name\",\"type\":\"string\"},{\"name\":\"u_price\", \"type\": \"float\"}, {\"name\":\"u_quantity\", \"type\": \"int\"}]}"
}'

log "Doing an admin operation with read user - expected to fail"
set +e
curl -X GET -u read:read http://localhost:8081/subjects
set -e
log "Doing an admin operation with admin user - expected to succeed"
curl -X GET -u admin:admin http://localhost:8081/subjects
log "Getting a subject with read user - expected to succeed"
set +e
curl -X GET -u read:read http://localhost:8081/subjects/my-topic-value/versions

# property auto.register.schemas was added in 5.5.2, need to use auto.register for previous versions #1651
AUTO_REGISTER_PROPERTY="auto.register.schemas"
if ! version_gt $TAG_BASE "5.5.2"; then
    AUTO_REGISTER_PROPERTY="auto.register"
fi
log "Testing with a producer (read:read) and --property $AUTO_REGISTER_PROPERTY=true, it will fail"
set +e
docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="read:read" --topic my-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' --property $AUTO_REGISTER_PROPERTY=true << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF
set -e
# org.apache.kafka.common.errors.SerializationException: Error registering Avro schema{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price","type":"float"},{"name":"u_quantity","type":"int"}]}
# Caused by: io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException: User is denied operation Write on Subject: my-topic-value; error code: 40301
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.sendHttpRequest(RestService.java:295)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.httpRequest(RestService.java:355)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:498)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:489)
#         at io.confluent.kafka.schemaregistry.client.rest.RestService.registerSchema(RestService.java:462)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.registerAndGetId(CachedSchemaRegistryClient.java:214)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:276)
#         at io.confluent.kafka.schemaregistry.client.CachedSchemaRegistryClient.register(CachedSchemaRegistryClient.java:252)
#         at io.confluent.kafka.serializers.AbstractKafkaAvroSerializer.serializeImpl(AbstractKafkaAvroSerializer.java:84)
#         at io.confluent.kafka.formatter.AvroMessageReader$AvroMessageSerializer.serialize(AvroMessageReader.java:168)
#         at io.confluent.kafka.formatter.SchemaMessageReader.readMessage(SchemaMessageReader.java:317)
#         at kafka.tools.ConsoleProducer$.main(ConsoleProducer.scala:51)
#         at kafka.tools.ConsoleProducer.main(ConsoleProducer.scala)


log "Testing with a producer (read:read) and --property $AUTO_REGISTER_PROPERTY=false, it will work"
docker exec -i connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="read:read" --topic my-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"u_name","type":"string"},{"name":"u_price", "type": "float"}, {"name":"u_quantity", "type": "int"}]}' --property $AUTO_REGISTER_PROPERTY=false << EOF
{"u_name": "scissors", "u_price": 2.75, "u_quantity": 3}
{"u_name": "tape", "u_price": 0.99, "u_quantity": 10}
{"u_name": "notebooks", "u_price": 1.99, "u_quantity": 5}
EOF