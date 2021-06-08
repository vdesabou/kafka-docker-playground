#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Generating data"
docker exec -i connect bash -c "mkdir -p /tmp/kafka-connect/examples/ && curl -sSL https://raw.githubusercontent.com/streamthoughts/kafka-connect-file-pulse/master/datasets/quickstart-musics-dataset.csv -o /tmp/kafka-connect/examples/quickstart-musics-dataset.csv"


log "Creating CSV FilePulse Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data @connect-file-pulse-quickstart-csv.json \
     http://localhost:8083/connectors/filepulse-source-csv/config | jq .


sleep 5

log "Verify we have received the data in connect-file-pulse-quickstart-csv topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic connect-file-pulse-quickstart-csv --from-beginning --max-messages 10