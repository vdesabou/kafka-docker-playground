#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

if [ ! -f "${DIR}/data/input/tsv-spooldir-source.tsv" ]
then
     log "Generating data"
     curl "https://api.mockaroo.com/api/b10f7e90?count=1000&key=25fd9c80" > "${DIR}/data/input/tsv-spooldir-source.tsv"
fi

log "Creating TSV Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": "tsv-spooldir-source.tsv",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "spooldir-tsv-topic",
                    "schema.generation.enabled": "true",
                    "csv.first.row.as.header": "true",
                    "csv.separator.char": "9"
          }' \
     http://localhost:8083/connectors/TsvSpoolDir/config | jq .


sleep 5

log "Verify we have received the data in spooldir-tsv-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic spooldir-tsv-topic --from-beginning --max-messages 10