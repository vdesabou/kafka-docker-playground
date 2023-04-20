#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.2.99"; then
    logwarn "WARN: Connect Secret Registry is available since CP 5.3 only"
    exit 111
fi

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Sending messages to topic rbac_topic"
seq -f "{\"f1\": \"This is a message sent with RBAC SASL/PLAIN authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_without_interceptors.config

log "Checking messages from topic rbac_topic"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_topic  --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_without_interceptors.config --consumer-property group.id=clientAvro --from-beginning --max-messages 1

log "Registering secret username with superUser"
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "connectorSA"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/username/versions | jq .

log "Registering secret password with superUser"
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "connectorSA"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/password/versions | jq .

log "Registering secret my-smt-password with superUser"
curl -X POST \
     -u superUser:superUser \
     -H "Content-Type: application/json" \
     --data '{
               "secret": "this-is-my-secret-value"
          }' \
     http://localhost:8083/secret/paths/my-rbac-connector/keys/my-smt-password/versions | jq .

log "Creating FileStream Sink connector"
curl -X PUT \
     -u connectorSubmitter:connectorSubmitter \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
               "topics": "rbac_topic",
               "file": "/tmp/output.json",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter.basic.auth.user.info": "${secret:my-rbac-connector:username}:${secret:my-rbac-connector:username}",
               "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"${secret:my-rbac-connector:username}\" password=\"${secret:my-rbac-connector:password}\" metadataServerUrls=\"http://broker:8091\";",
               "transforms": "InsertField",
               "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
               "transforms.InsertField.static.field": "AddedBySMT",
               "transforms.InsertField.static.value": "${secret:my-rbac-connector:my-smt-password}"
          }' \
     http://localhost:8083/connectors/my-rbac-connector/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 1,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 2,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 3,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 4,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 5,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 6,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 7,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 8,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 9,AddedBySMT=this-is-my-secret-value}
# Struct{f1=This is a message sent with RBAC SASL/PLAIN authentication 10,AddedBySMT=this-is-my-secret-value}
