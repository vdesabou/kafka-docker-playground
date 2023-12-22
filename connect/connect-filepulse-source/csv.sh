#!/bin/bash
set -e

if [ -z "$CONNECTOR_TAG" ]
then
    CONNECTOR_TAG=2.9.0
fi

if [ ! -f streamthoughts-kafka-connect-file-pulse-${CONNECTOR_TAG}.zip ]
then
    curl -L -o streamthoughts-kafka-connect-file-pulse-${CONNECTOR_TAG}.zip https://github.com/streamthoughts/kafka-connect-file-pulse/releases/download/v${CONNECTOR_TAG}/streamthoughts-kafka-connect-file-pulse-${CONNECTOR_TAG}.zip
fi

export CONNECTOR_ZIP=$PWD/streamthoughts-kafka-connect-file-pulse-${CONNECTOR_TAG}.zip
VERSION=$CONNECTOR_TAG
unset CONNECTOR_TAG

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.0"
then
    if version_gt $VERSION "1.9.9"
    then
        log "This connector does not support JDK 8 starting from version 2.0"
        exit 111
    fi
fi

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Generating data"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL -k https://raw.githubusercontent.com/streamthoughts/kafka-connect-file-pulse/master/datasets/quickstart-musics-dataset.csv -o /tmp/kafka-connect/examples/quickstart-musics-dataset.csv"


log "Creating CSV FilePulse Source connector"
# if ! version_gt $CONNECTOR_TAG "1.9.9"
# then
#      # Version 1.x
#      curl -X PUT \
#           -H "Content-Type: application/json" \
#           --data @connect-file-pulse-quickstart-csv-1x.json \
#           http://localhost:8083/connectors/filepulse-source-csv/config | jq .
# else
     # Version 2.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data @connect-file-pulse-quickstart-csv-2x.json \
          http://localhost:8083/connectors/filepulse-source-csv/config | jq .
# fi

sleep 30

log "Verify we have received the data in connect-file-pulse-quickstart-csv topic"
playground topic consume --topic connect-file-pulse-quickstart-csv --min-expected-messages 10 --timeout 60