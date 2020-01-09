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
     echo -e "\033[0;33mGenerating data\033[0m"
     curl "https://api.mockaroo.com/api/b10f7e90?count=1000&key=25fd9c80" > "${DIR}/data/input/tsv-spooldir-source.tsv"
fi

echo -e "\033[0;33mCreating TSV Spool Dir Source connector\033[0m"
docker exec connect \
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

echo -e "\033[0;33mVerify we have received the data in spooldir-tsv-topic topic\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic spooldir-tsv-topic --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 10