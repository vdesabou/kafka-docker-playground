#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-firebase-source
GCP_KEYFILE="${PWD}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "ERROR: either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${GCP_KEYFILE} ]
    then
        GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi
cd -

if [ ! -z "$CI" ]
then
     # running with github actions


     log "Removing all data"
     docker run -p 9005:9005 -e FIREBASE_TOKEN="$FIREBASE_TOKEN" -e PROJECT=$GCP_PROJECT -i kamshak/firebase-tools-docker firebase database:remove / -y --token "$FIREBASE_TOKEN" --project "$GCP_PROJECT"
     log "Adding data from musicBlog.json"
     docker run -p 9005:9005 -v ${DIR}/musicBlog.json:/tmp/musicBlog.json -e FIREBASE_TOKEN="$FIREBASE_TOKEN" -e PROJECT=$GCP_PROJECT -i kamshak/firebase-tools-docker firebase database:set / /tmp/musicBlog.json -y --token "$FIREBASE_TOKEN" --project "$GCP_PROJECT"
     log "Verifying data is in Firebase"
     docker run -p 9005:9005 -e FIREBASE_TOKEN="$FIREBASE_TOKEN" -e PROJECT=$GCP_PROJECT -i kamshak/firebase-tools-docker firebase database:get / --token "$FIREBASE_TOKEN" --project "$GCP_PROJECT" | jq .
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating GCP Firebase Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.firebase.FirebaseSourceConnector",
               "tasks.max" : "1",
               "gcp.firebase.credentials.path": "/tmp/keyfile.json",
               "gcp.firebase.database.reference": "https://'"$GCP_PROJECT"'.firebaseio.com/musicBlog",
               "gcp.firebase.snapshot":"true",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/firebase-source/config | jq .

sleep 10

log "Verify messages are in topic artists"
playground topic consume --topic artists --expected-messages 3

log "Verify messages are in topic songs"
playground topic consume --topic songs --expected-messages 3
