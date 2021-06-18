#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh

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

log "display offsets"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic connect-offsets --from-beginning --property print.key=true --max-messages 1

log "Verify we have received the data in filestream topic: we only get the last 9, data is lost"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic filestream --from-beginning --max-messages 18