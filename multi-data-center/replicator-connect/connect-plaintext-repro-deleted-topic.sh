#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/mdc-plaintext/start.sh

log "Sending 10 sales in sales_EUROPE topic in Europe cluster"
seq -f "european_sale_%g `date +%s`" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE"

log "Replicate in the US"

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
          "dest.kafka.bootstrap.servers": "broker-us:9092",
          "confluent.topic.replication.factor": 1,
          "provenance.header.enable": true,
          "topic.whitelist": "sales_EUROPE"
          }' \
     http://localhost:8083/connectors/replicate-europe-to-us/config | jq .

sleep 60

log "Verify we have received the 10 sales in US cluster"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_EUROPE' --from-beginning --max-messages 10"


log "Deleting topic sales_EUROPE in US cluster"
docker exec broker-us kafka-topics --delete --topic sales_EUROPE --bootstrap-server broker-us:9092

sleep 10

log "Sending 10 other sales in sales_EUROPE topic in Europe cluster"
seq -f "european_sale_%g `date +%s`" 10 | docker container exec -i connect-europe bash -c "kafka-console-producer --broker-list broker-europe:9092 --topic sales_EUROPE"

# [2021-06-21 08:20:32,102] WARN [Producer clientId=connect-worker-producer-us] Got error produce response with correlation id 6 on topic-partition sales_EUROPE-0, retrying (2147483646 attempts left). Error: UNKNOWN_TOPIC_OR_PARTITION (org.apache.kafka.clients.producer.internals.Sender)
# [2021-06-21 08:20:32,102] WARN [Producer clientId=connect-worker-producer-us] Received unknown topic or partition error in produce request on partition sales_EUROPE-0. The topic-partition may not exist or the user may not have Describe access to it (org.apache.kafka.clients.producer.internals.Sender)
# [2021-06-21 08:20:32,114] WARN [Producer clientId=connect-worker-producer-us] Error while fetching metadata with correlation id 7 : {sales_EUROPE=LEADER_NOT_AVAILABLE} (org.apache.kafka.clients.NetworkClient)

sleep 60

log "Verify we have received the 10 last sales only in US cluster, we have lost the 10 first as expected"
docker container exec -i connect-europe bash -c "kafka-console-consumer --bootstrap-server broker-us:9092 --whitelist 'sales_EUROPE' --from-beginning --max-messages 10"
