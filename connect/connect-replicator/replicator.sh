#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Sending messages to topic test-topic"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-topic

echo "Creating Replicator connector"
docker exec connect \
      curl -X PUT \
      -H "Content-Type: application/json" \
      --data '{
         "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
               "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "src.consumer.group.id": "duplicate-topic",
               "confluent.topic.replication.factor": 1,
               "provenance.header.enable": true,
               "topic.whitelist": "test-topic",
               "topic.rename.format": "test-topic-duplicate",
               "dest.kafka.bootstrap.servers": "broker:9092",
               "src.kafka.bootstrap.servers": "broker:9092"
           }' \
      http://localhost:8083/connectors/duplicate-topic/config | jq .

sleep 10

echo "Verify we have received the data in test-topic-duplicate topic"
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-topic-duplicate --from-beginning --max-messages 10