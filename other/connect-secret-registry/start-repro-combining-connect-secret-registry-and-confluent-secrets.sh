#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.2.99"; then
    logwarn "WARN: Confluent Secrets is available since CP 5.3 only"
    exit 111
fi

rm -f ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets/secret.txt
rm -f ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets/CONFLUENT_SECURITY_MASTER_KEY
docker run -i --rm -v ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets:/secrets cnfldemos/tools:0.3 bash -c '
echo "Generate master key"
confluent-v1 secret master-key generate --local-secrets-file /secrets/secret.txt --passphrase @/secrets/passphrase.txt > /tmp/result.log 2>&1
cat /tmp/result.log
export CONFLUENT_SECURITY_MASTER_KEY=$(grep "Master Key" /tmp/result.log | cut -d"|" -f 3 | sed "s/ //g" | tail -1 | tr -d "\n")
echo "$CONFLUENT_SECURITY_MASTER_KEY" > /secrets/CONFLUENT_SECURITY_MASTER_KEY
echo "Encrypting my-secret-property in file my-config-file.properties"
confluent-v1 secret file encrypt --local-secrets-file /secrets/secret.txt --remote-secrets-file /etc/kafka/secrets/secret.txt --config my-secret-property --config-file /secrets/my-config-file.properties
'

export CONFLUENT_SECURITY_MASTER_KEY=$(cat ${DIR}/repro-combining-connect-secret-registry-and-confluent-secrets/secrets/CONFLUENT_SECURITY_MASTER_KEY | sed 's/ //g' | tail -1 | tr -d '\n')
log "Exporting CONFLUENT_SECURITY_MASTER_KEY=$CONFLUENT_SECURITY_MASTER_KEY"

${DIR}/../../environment/rbac-sasl-plain/start.sh "${PWD}/docker-compose.rbac-sasl-plain.yml"

log "Sending messages to topic rbac_topic"
seq -f "{\"f1\": \"This is a message sent with RBAC SASL/PLAIN authentication %g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}' --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --producer.config /etc/kafka/secrets/client_sasl_plain.config

log "Checking messages from topic rbac_topic"
docker exec -i connect kafka-avro-console-consumer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic rbac_topic  --property schema.registry.url=http://schema-registry:8081 --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info=clientAvroCli:clientAvroCli --consumer.config /etc/kafka/secrets/client_sasl_plain.config --consumer-property group.id=clientAvro --from-beginning --max-messages 1

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

log "Creating FileStream Sink connector"
curl -X PUT \
     -u connectorSubmitter:connectorSubmitter \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSink",
               "topics": "rbac_topic",
               "file": "/tmp/output.json",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter.basic.auth.user.info": "connectorSA:connectorSA",
               "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"${secret:my-rbac-connector:username}\" password=\"${secret:my-rbac-connector:password}\" metadataServerUrls=\"http://broker:8091\";"
          }' \
     http://localhost:8083/connectors/my-rbac-connector/config | jq .


sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json
