#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# if ! version_gt $TAG_BASE "5.9.0"
# then
#     if version_gt $CONNECTOR_TAG "1.9.9"
#     then
#         log "This connector does not support JDK 8 starting from version 2.0"
#         exit 111
#     fi
# fi

if [ ! -d streamthoughts-kafka-connect-file-pulse-2.9.0 ]
then
    curl -L -o streamthoughts-kafka-connect-file-pulse-2.9.0.zip https://github.com/streamthoughts/kafka-connect-file-pulse/releases/download/v2.9.0/streamthoughts-kafka-connect-file-pulse-2.9.0.zip
    unzip streamthoughts-kafka-connect-file-pulse-2.9.0.zip
fi


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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

sleep 5

log "Verify we have received the data in connect-file-pulse-quickstart-csv topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic connect-file-pulse-quickstart-csv --from-beginning --max-messages 10