#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-sasl-plain/start.sh "${PWD}/docker-compose.sasl-plain.yml"

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE --producer.config /etc/kafka/client.properties

log "Sending sales in US cluster"
seq -f "us_sale_%g ${RANDOM}" 10 | docker container exec -i broker-us kafka-console-producer --broker-list localhost:9092 --topic sales_US --producer.config /etc/kafka/client.properties

log "Consolidating all sales in the US"

docker container exec connect-us \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-europe-to-us",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "src.kafka.security.protocol" : "SASL_PLAINTEXT",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "src.kafka.sasl.mechanism": "PLAIN",
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "dest.kafka.security.protocol" : "SASL_PLAINTEXT",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "dest.kafka.sasl.mechanism": "PLAIN",
          "confluent.topic.replication.factor": 1,
          "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
          "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "confluent.topic.sasl.mechanism": "PLAIN",
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq_docker_cli .


log "Consolidating all sales in Europe"

docker container exec connect-europe \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.consumer.group.id": "replicate-us-to-europe",
          "src.kafka.bootstrap.servers": "broker-us:9092",
          "src.kafka.security.protocol" : "SASL_PLAINTEXT",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "src.kafka.sasl.mechanism": "PLAIN",
          "dest.kafka.bootstrap.servers": "broker-europe:9092",
          "dest.kafka.security.protocol" : "SASL_PLAINTEXT",
          "dest.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "dest.kafka.sasl.mechanism": "PLAIN",
          "confluent.topic.replication.factor": 1,
          "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
          "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "confluent.topic.sasl.mechanism": "PLAIN",
          "provenance.header.enable": true,
          "topic.whitelist": "sales_US"
          }' \
     http://localhost:8083/connectors/replicate-us-to-europe/config | jq_docker_cli .


log "Verify we have received the data in all the sales_ topics in EUROPE"
timeout 60 docker container exec broker-europe kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/client.properties

log "Verify we have received the data in all the sales_ topics in the US"
timeout 60 docker container exec broker-us kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_.*" --from-beginning --max-messages 20 --property metadata.max.age.ms 30000 --consumer.config /etc/kafka/client.properties

