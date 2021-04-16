#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ${DIR}/data/input
mkdir -p ${DIR}/data/error
mkdir -p ${DIR}/data/finished

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

if [ ! -f "${DIR}/data/input/fix.json" ]
then
     log "Generating data"
     curl "https://raw.githubusercontent.com/jcustenborder/kafka-connect-spooldir/master/src/test/resources/com/github/jcustenborder/kafka/connect/spooldir/SpoolDirLineDelimitedSourceConnector/fix.json" > "${DIR}/data/input/fix.json"
fi

INPUT_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/input/"
ERROR_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/error/"
FINISHED_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/finished/"

log "Creating Line Delimited Spool Dir Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirLineDelimitedSourceConnector",
               "input.file.pattern": "fix.json",
               "input.path": "'"$INPUT_PATH"'",
               "error.path": "'"$ERROR_PATH"'",
               "finished.path": "'"$FINISHED_PATH"'",
               "halt.on.error": "false",
               "topic": "fix-topic",
               "schema.generation.enabled": "true"
          }' \
     http://localhost:8083/connectors/spool-dir/config | jq .


sleep 5

log "Verify we have received the data in fix-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic fix-topic --from-beginning --max-messages 10