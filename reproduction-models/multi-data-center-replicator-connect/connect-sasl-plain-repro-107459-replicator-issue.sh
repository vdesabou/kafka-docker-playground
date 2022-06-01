#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

#${DIR}/../../environment/mdc-sasl-plain/start.sh "${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml"

docker-compose -f ${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml build
docker-compose -f ${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml down -v --remove-orphans
docker-compose -f ${PWD}/docker-compose.mdc-sasl-plain.repro-107459-replicator-issue.yml up -d


../../scripts/wait-for-connect-and-controlcenter.sh connect-us
../../scripts/wait-for-connect-and-controlcenter.sh connect-europe

log "Sending sales in Europe cluster"
seq -f "european_sale_%g ${RANDOM}" 10 | docker container exec -i broker-europe kafka-console-producer --broker-list localhost:9092 --topic sales_EUROPE --producer.config /etc/kafka/client.properties

# docker container exec connect-europe \
# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/io.confluent.connect.replicator \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
#  "level": "INFO"
# }'

log "create replicator on connect-europe (PLAIN) with src=europe and dest=us (PLAINTEXT)"
docker container exec connect-europe \
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
          "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
          "src.kafka.bootstrap.servers": "broker-europe:9092",
          "src.kafka.security.protocol" : "SASL_PLAINTEXT",
          "src.kafka.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
          "src.kafka.sasl.mechanism": "PLAIN",
          
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "_dest.kafka.sasl.mechanism": "PLAIN",

          "confluent.topic.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

sleep 120

log "Verify we have received the data in is sales_EUROPE in US"
docker container exec broker-us kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "sales_EUROPE" --from-beginning --max-messages 10 

# docker container exec broker-europe kafka-console-consumer --bootstrap-server localhost:9092 --whitelist "connect-europe.config" --from-beginning --consumer.config /etc/kafka/client.properties --property print.key=true
