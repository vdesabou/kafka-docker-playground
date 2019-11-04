#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

if [ ! -f "${DIR}/data/input/fix.json" ]
then
     echo "Generating data"
     curl "https://raw.githubusercontent.com/jcustenborder/kafka-connect-spooldir/master/src/test/resources/com/github/jcustenborder/kafka/connect/spooldir/SpoolDirLineDelimitedSourceConnector/fix.json" > "${DIR}/data/input/fix.json"
fi

echo "Creating Line Delimited Spool Dir Source connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "LineDelimitedSpoolDir",
               "config": {
                    "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirLineDelimitedSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": "fix.json",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "fix-topic",
                    "schema.generation.enabled": "true"
          }}' \
     http://localhost:8083/connectors | jq .


sleep 5

echo "Verify we have received the data in fix-topic topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic fix-topic --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 10