#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml"

DD_API_KEY=${DD_API_KEY:-$1}
DD_SITE=${DD_SITE:-$2}

if [ -z "$DD_API_KEY" ]
then
     logerror "DD_API_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DD_SITE" ]
then
     logerror "DD_SITE is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

log "Restarting Datadog agent"
docker container restart datadog

sleep 10

log "Sending messages to topic test-topic"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-topic

log "Creating Replicator connector"
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

log "Verify we have received the data in test-topic-duplicate topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-topic-duplicate --from-beginning --max-messages 10


log "Generating some data to a perf-test topic"
docker exec broker kafka-producer-perf-test --topic perf-test --num-records 200000 --record-size 1000 --throughput 100000 --producer-props bootstrap.servers=broker:9092

docker exec broker kafka-consumer-perf-test --topic perf-test --messages 200000  --broker-list broker:9092