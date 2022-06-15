#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cp repro-107746-certs-create.sh ../../environment/sasl-ssl/security/certs-create.sh

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.repro-107746-issue-in-confluent-replicator.yml"

log "########"
log "##  SASL_SSL authentication"
log "########"

log "Sending messages to topic test-topic-sasl-ssl"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-topic-sasl-ssl --producer.config /etc/kafka/secrets/client_without_interceptors.config

log "Creating Confluent Replicator connector with SASL_SSL authentication"
curl -X PUT \
     --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
                    "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
                    "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
                    "src.consumer.group.id": "duplicate-topic",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "confluent.topic.ssl.truststore.password" : "confluent",
                    "confluent.topic.security.protocol" : "SASL_SSL",
                    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
                    "confluent.topic.sasl.mechanism": "PLAIN",
                    "provenance.header.enable": true,
                    "topic.whitelist": "test-topic-sasl-ssl",
                    "topic.rename.format": "test-topic-sasl-ssl-duplicate",
                    "dest.kafka.bootstrap.servers": "broker-other:9092",
                    "dest.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect-other.truststore.jks",
                    "dest.kafka.ssl.truststore.password" : "confluent",
                    "dest.kafka.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect-other.keystore.jks",
                    "dest.kafka.ssl.keystore.password" : "confluent",
                    "dest.kafka.ssl.key.password" : "confluent",
                    "dest.kafka.security.protocol" : "SSL",

                    "producer.override.bootstrap.servers": "broker-other:9092",
                    "producer.override.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect-other.truststore.jks",
                    "producer.override.ssl.truststore.password" : "confluent",
                    "producer.override.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect-other.keystore.jks",
                    "producer.override.ssl.keystore.password" : "confluent",
                    "producer.override.ssl.key.password" : "confluent",
                    "producer.override.security.protocol" : "SSL",

                    "src.kafka.bootstrap.servers": "broker:9092",
                    "src.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "src.kafka.ssl.truststore.password" : "confluent",
                    "src.kafka.security.protocol" : "SASL_SSL",
                    "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
                    "src.kafka.sasl.mechanism": "PLAIN"
          }' \
     https://localhost:8083/connectors/replicator-sasl-ssl/config | jq .


sleep 10

log "Verify we have received the data in test-topic-sasl-ssl-duplicate topic"
docker cp ../../environment/2way-ssl/security/client_without_interceptors_2way_ssl.config broker-other:/tmp/
timeout 60 docker exec broker-other kafka-console-consumer --bootstrap-server broker-other:9092 --topic test-topic-sasl-ssl-duplicate --from-beginning --max-messages 10 --consumer.config /tmp/client_without_interceptors_2way_ssl.config