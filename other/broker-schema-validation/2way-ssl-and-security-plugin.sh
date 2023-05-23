#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: Broker Validation is available since CP 5.4 only"
    exit 111
fi

${DIR}/../../environment/2way-ssl/start.sh "${PWD}/docker-compose.2way-ssl.security-plugin.yml"

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

log "Create topic topic-validation"
docker exec broker kafka-topics --bootstrap-server broker:9092 --create --topic topic-validation --partitions 1 --replication-factor 1 --command-config /etc/kafka/secrets/client_without_interceptors.config --config confluent.key.schema.validation=true --config confluent.value.schema.validation=true

log "Describe topic"
docker exec broker kafka-topics \
   --describe \
   --topic topic-validation \
   --bootstrap-server broker:9092 \
   --command-config /etc/kafka/secrets/client_without_interceptors.config

log "Registering a subject with write user"
curl -X POST \
   -H "Content-Type: application/vnd.schemaregistry.v1+json" \
   --cert ../../environment/2way-ssl/security/connect.certificate.pem --key ../../environment/2way-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/2way-ssl/security/snakeoil-ca-1.crt \
   -u write:write \
   --data '{ "schema": "[ { \"type\":\"record\", \"name\":\"user\", \"fields\": [ {\"name\":\"userid\",\"type\":\"long\"}, {\"name\":\"username\",\"type\":\"string\"} ]} ]" }' \
   https://localhost:8081/subjects/topic-validation-value/versions

log "Sending a non-Avro record, it should fail"
docker exec -i connect kafka-console-producer \
     --topic topic-validation \
     --broker-list broker:9092 \
     --producer.config /etc/kafka/secrets/client_without_interceptors.config << EOF
{"userid":1,"username":"RODRIGUEZ"}
EOF

log "Sending a Avro record, it should work"
docker exec -i connect kafka-avro-console-producer \
     --topic topic-validation \
     --broker-list broker:9092 \
     --property basic.auth.credentials.source=USER_INFO \
     --property schema.registry.basic.auth.user.info="write:write" \
     --property schema.registry.url=https://schema-registry:8081 \
     --property schema.registry.ssl.truststore.location=/etc/kafka/secrets/kafka.client.truststore.jks \
     --property schema.registry.ssl.truststore.password=confluent \
     --property schema.registry.ssl.keystore.location=/etc/kafka/secrets/kafka.client.keystore.jks \
     --property schema.registry.ssl.keystore.password=confluent \
     --property value.schema='{"type":"record","name":"user","fields":[{"name":"userid","type":"long"},{"name":"username","type":"string"}]}' \
     --producer.config /etc/kafka/secrets/client_without_interceptors.config << EOF
{"userid":1,"username":"RODRIGUEZ"}
EOF

log "Verify we have the record"
playground topic consume --topic topic-validation --expected-messages 1