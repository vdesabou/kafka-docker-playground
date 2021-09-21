#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Generating 10 messages"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL 'https://api.mockaroo.com/api/17c84440?count=10&key=25fd9c80' -o /tmp/kafka-connect/examples/file.json"

log "Creating FileStream Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "FileStreamSource",
               "topic": "filestream",
               "file": "/tmp/kafka-connect/examples/file.json",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/filestream-source/config | jq .

sleep 5

log "Verify we have received the data in filestream topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic filestream --from-beginning --max-messages 9

log "display offsets"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1

log "Deleting topic"
docker exec broker kafka-topics --delete --topic filestream --bootstrap-server broker:9092

log "Generating 10 other messages"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL 'https://api.mockaroo.com/api/17c84440?count=10&key=25fd9c80' -o /tmp/kafka-connect/examples/file2.json && cat /tmp/kafka-connect/examples/file2.json >> /tmp/kafka-connect/examples/file.json"

# [2021-06-18 16:05:44,675] WARN [Producer clientId=connect-worker-producer] Got error produce response with correlation id 7 on topic-partition filestream-0, retrying (2147483646 attempts left). Error: UNKNOWN_TOPIC_OR_PARTITION (org.apache.kafka.clients.producer.internals.Sender)
# [2021-06-18 16:05:44,676] WARN [Producer clientId=connect-worker-producer] Received unknown topic or partition error in produce request on partition filestream-0. The topic-partition may not exist or the user may not have Describe access to it (org.apache.kafka.clients.producer.internals.Sender)

log "display offsets"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1

log "Verify we have received the data in filestream topic: we only get the last 9, data is lost"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic filestream --from-beginning --max-messages 18