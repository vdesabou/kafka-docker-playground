#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
log "Generating data"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL -k 'https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80' -o /tmp/kafka-connect/examples/file.json"

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
               "value.converter.schemas.enable": "false",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/filestream-source/config | jq .


sleep 5

log "Verify we have received the data in filestream topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic filestream --from-beginning --max-messages 10
