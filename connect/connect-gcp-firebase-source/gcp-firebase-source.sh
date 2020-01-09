#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     log "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating GCP Firebase Source connector"
docker exec -e PROJECT="$PROJECT" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.firebase.FirebaseSourceConnector",
                    "tasks.max" : "1",
                    "gcp.firebase.credentials.path": "/root/keyfiles/keyfile.json",
                    "gcp.firebase.database.reference": "https://'"$PROJECT"'.firebaseio.com/musicBlog",
                    "gcp.firebase.snapshot":"true",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/firebase-source/config | jq .

sleep 10

log "Verify messages are in topic artists"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic artists --from-beginning --max-messages 3

log "Verify messages are in topic songs"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic songs --from-beginning --max-messages 3
