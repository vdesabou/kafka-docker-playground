#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.sasl-ssl.yml"

log "########"
log "##  SASL_SSL authentication"
log "########"

log "Sending messages to topic test-topic-sasl-ssl"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-topic-sasl-ssl --producer.config /etc/kafka/secrets/client_without_interceptors.config

log "Creating Confluent Replicator connector with SASL_SSL authentication"
playground connector create-or-update --connector replicator-sasl-ssl << EOF
{
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
                    "dest.kafka.bootstrap.servers": "broker:9092",
                    "dest.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "dest.kafka.ssl.truststore.password" : "confluent",
                    "dest.kafka.security.protocol" : "SASL_SSL",
                    "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
                    "dest.kafka.sasl.mechanism": "PLAIN",
                    "src.kafka.bootstrap.servers": "broker:9092",
                    "src.kafka.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
                    "src.kafka.ssl.truststore.password" : "confluent",
                    "src.kafka.security.protocol" : "SASL_SSL",
                    "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
                    "src.kafka.sasl.mechanism": "PLAIN"
          }
EOF


sleep 10

log "Verify we have received the data in test-topic-sasl-ssl-duplicate topic"
playground topic consume --topic test-topic-sasl-ssl-duplicate --min-expected-messages 10 --timeout 60