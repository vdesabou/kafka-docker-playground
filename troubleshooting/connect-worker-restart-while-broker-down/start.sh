#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

docker-compose down -v --remove-orphans
docker-compose up -d
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh "connect1"
${DIR}/../../scripts/wait-for-connect-and-controlcenter.sh "connect2"

docker exec broker1 kafka-topics --create --topic test-topic --partitions 10 --replication-factor 3 --zookeeper zookeeper:2181

log "Sending messages to topic test-topic"
seq 10 | docker exec -i broker1 kafka-console-producer --broker-list broker1:9092 --topic test-topic

log "Creating Replicator connector"
curl -X PUT \
      -H "Content-Type: application/json" \
      --data '{
              "tasks.max": "10",
              "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
               "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
               "src.consumer.group.id": "duplicate-topic",
               "confluent.topic.replication.factor": 3,
               "provenance.header.enable": true,
               "topic.whitelist": "test-topic",
               "topic.rename.format": "test-topic-duplicate",
               "dest.kafka.bootstrap.servers": "broker1:9092,broker2:9092,broker3:9092",
               "src.kafka.bootstrap.servers": "broker1:9092,broker2:9092,broker3:9092"
           }' \
      http://localhost:8083/connectors/replicator/config | jq .

sleep 10

log "Verify we have received the data in test-topic-duplicate topic"
timeout 60 docker exec broker1 kafka-console-consumer --bootstrap-server broker1:9092 --topic test-topic-duplicate --from-beginning --max-messages 10

sleep 5

log "Getting tasks placement"

curl --request GET \
  --url http://localhost:8083/connectors/replicator/status \
  --header 'accept: application/json' | jq


log "Stop broker 1"
#docker container stop broker1
docker container kill broker1
# if broker 2 or 3 is down, no problem
# docker container stop broker2

docker container stop connect2

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/replicator/status \
  --header 'accept: application/json' | jq

docker container start connect2

# commented as eager is used
# log "sleep 5 minutes (scheduled.rebalance.max.delay.ms), after this time all tasks should be RUNNING (no more UNASSIGNED)"
# sleep 310
sleep 60

log "Getting tasks placement"
curl --request GET \
  --url http://localhost:8083/connectors/replicator/status \
  --header 'accept: application/json' | jq