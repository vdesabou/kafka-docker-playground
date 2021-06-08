#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ${DIR}/data/input

# workaround for issue on linux, see https://github.com/vdesabou/kafka-docker-playground/issues/851#issuecomment-821151962
chmod -R a+rw ${DIR}/data

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

if [ ! -f "${DIR}/data/input/quickstart-musics-dataset.csv" ]
then
     log "Generating data"
     curl -sSL https://raw.githubusercontent.com/streamthoughts/kafka-connect-file-pulse/master/datasets/quickstart-musics-dataset.csv -o ${DIR}/data/input/quickstart-musics-dataset.csv
fi

export DIRECTORY_PATH="${CONNECT_CONTAINER_HOME_DIR}/data/input/"

log "Creating CSV FilePulse Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data @connect-file-pulse-quickstart-csv.json \
     http://localhost:8083/connectors/neo4j-sink/config | jq .


sleep 5

log "Verify we have received the data in connect-file-pulse-quickstart-csv topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic connect-file-pulse-quickstart-csv --from-beginning --max-messages 10