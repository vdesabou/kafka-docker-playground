#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

if [ ! -f "${DIR}/data/input/fix.json" ]
then
     echo -e "\033[0;33mGenerating data\033[0m"
     curl "https://raw.githubusercontent.com/jcustenborder/kafka-connect-spooldir/master/src/test/resources/com/github/jcustenborder/kafka/connect/spooldir/SpoolDirLineDelimitedSourceConnector/fix.json" > "${DIR}/data/input/fix.json"
fi

echo -e "\033[0;33mCreating Line Delimited Spool Dir Source connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirLineDelimitedSourceConnector",
                    "input.path": "/root/data/input",
                    "input.file.pattern": "fix.json",
                    "error.path": "/root/data/error",
                    "finished.path": "/root/data/finished",
                    "halt.on.error": "false",
                    "topic": "fix-topic",
                    "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/spool-dir/config | jq .


sleep 5

echo -e "\033[0;33mVerify we have received the data in fix-topic topic\033[0m"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic fix-topic --property schema.registry.url=http://schema-registry:8081 --from-beginning --max-messages 10