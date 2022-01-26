#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-89666-connector-silently-fails-to-generate-messages.yml"

log "activate TRACE for io.confluent.kafka.connect.datagen"
curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.kafka.connect.datagen \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Create topic schema1"
curl -s -X PUT \
      -H "Content-Type: application/json" \
      --data '{
                "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                "kafka.topic": "schema1",
                "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                "value.converter.schemas.enable": "false",
                "max.interval": 1,
                "iterations": "10000",
                "tasks.max": "10",
                "schema.filename" : "/tmp/schemas/schema1.avro"
            }' \
      http://localhost:8083/connectors/datagen-schema1/config | jq

wait_for_datagen_connector_to_inject_data "schema1" "10"

sleep 10

log "Verify we have received the data in schema1 topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic schema1 --from-beginning --max-messages 1
