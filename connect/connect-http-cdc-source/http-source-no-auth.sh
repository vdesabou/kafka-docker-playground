#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.no-auth.yml"

log "Creating http-source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.castorm.kafka.connect.http.HttpSourceConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "http.request.url": "http://httpserver:8080/api/messages",
               "kafka.topic": "http-topic-messages"
          }' \
     http://localhost:8083/connectors/http-cdc-source/config | jq .


sleep 3

log "Send a message to HTTP server"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{"test":"value"}' \
     http://localhost:8080/api/messages | jq .


sleep 2

log "Verify we have received the data in http-topic-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic http-topic-messages --from-beginning --property print.key=true --max-messages 1
