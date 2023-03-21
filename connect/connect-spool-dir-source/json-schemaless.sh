#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Generate data"
docker exec -i connect bash -c 'mkdir -p /tmp/data/input/ && mkdir -p /tmp/data/error/ && mkdir -p /tmp/data/finished/ && curl -k "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > /tmp/data/input/json-spooldir-source.json'

log "Creating JSON Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirSchemaLessJsonSourceConnector",
               "input.file.pattern": ".*\\.json",
               "input.path": "/tmp/data/input",
               "error.path": "/tmp/data/error",
               "finished.path": "/tmp/data/finished",
               "halt.on.error": "false",
               "topic": "spooldir-schemaless-json-topic",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter"
          }' \
     http://localhost:8083/connectors/spool-dir/config | jq .


sleep 5

log "Verify we have received the data in spooldir-schemaless-json-topic topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic spooldir-schemaless-json-topic --from-beginning --max-messages 10

