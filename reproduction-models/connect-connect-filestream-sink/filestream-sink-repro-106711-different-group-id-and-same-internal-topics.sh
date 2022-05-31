#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export ENABLE_CONNECT_NODES=1
NB_CONNECTORS=10

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-106711-different-group-id-and-same-internal-topics.yml"

log "Sending messages to topic filestream"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic filestream << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF

OUTPUT_FILE="${CONNECT_CONTAINER_HOME_DIR}/data/ouput/file.json"

for((i=0;i<$NB_CONNECTORS;i++)); do
     log "Creating FileStream Sink connector $i"
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "tasks.max": "1",
                    "connector.class": "FileStreamSink",
                    "topics": "filestream",
                    "file": "/tmp/output.json",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
               }' \
          http://localhost:8083/connectors/filestream-sink$i/config | jq .
done



sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json


# connectors are deployed on every worker -> deleting it on one delete all others