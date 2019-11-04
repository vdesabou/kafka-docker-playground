#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
BUCKET_NAME=${1:-kafka-docker-playground}

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

if [ ! -f "${DIR}/data/input/json-spooldir-source.json" ]
then
     echo "Generating data"
     curl "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/data/input/json-spooldir-source.json"
fi

echo "Creating JSON Spool Dir Source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "SchemaLessJsonSpoolDir",
               "config": {
                    "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirSchemaLessJsonSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": "json-spooldir-source.json",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-schemaless-json-topic",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter"
          }}' \
     http://localhost:8083/connectors | jq .


sleep 5

echo "Verify we have received the data in spooldir-schemaless-json-topic topic"
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic spooldir-schemaless-json-topic --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 10

