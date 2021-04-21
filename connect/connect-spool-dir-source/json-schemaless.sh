#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+rw ${DIR}/data

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

if [ ! -f "${DIR}/data/input/json-spooldir-source.json" ]
then
     log "Generating data"
     curl "https://api.mockaroo.com/api/17c84440?count=500&key=25fd9c80" > "${DIR}/data/input/json-spooldir-source.json"
fi

INPUT_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/input/"
ERROR_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/error/"
FINISHED_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/finished/"

log "Creating JSON Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirSchemaLessJsonSourceConnector",
               "input.file.pattern": "json-spooldir-source.json",
               "input.path": "'"$INPUT_PATH"'",
               "error.path": "'"$ERROR_PATH"'",
               "finished.path": "'"$FINISHED_PATH"'",
               "halt.on.error": "false",
               "topic": "spooldir-schemaless-json-topic",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter"
          }' \
     http://localhost:8083/connectors/spool-dir/config | jq .


sleep 5

log "Verify we have received the data in spooldir-schemaless-json-topic topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic spooldir-schemaless-json-topic --from-beginning --max-messages 10

