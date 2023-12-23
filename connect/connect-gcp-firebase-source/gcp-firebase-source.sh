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

log "Removing all data"
docker run -p 9005:9005 -v $PWD/../../connect/connect-gcp-firebase-source/keyfile.json:/tmp/keyfile.json -e GOOGLE_APPLICATION_CREDENTIALS="/tmp/keyfile.json" -e PROJECT=$GCP_PROJECT -i andreysenov/firebase-tools firebase database:remove / --project "$GCP_PROJECT" --force
log "Adding data from musicBlog.json"
docker run -p 9005:9005 -v $PWD/../../connect/connect-gcp-firebase-source/keyfile.json:/tmp/keyfile.json -e GOOGLE_APPLICATION_CREDENTIALS="/tmp/keyfile.json" -v $PWD/../../connect/connect-gcp-firebase-source/musicBlog.json:/tmp/musicBlog.json -e PROJECT=$GCP_PROJECT -i andreysenov/firebase-tools firebase database:set / /tmp/musicBlog.json --project "$GCP_PROJECT" --force
log "Verifying data is in Firebase"
docker run -p 9005:9005 -v $PWD/../../connect/connect-gcp-firebase-source/keyfile.json:/tmp/keyfile.json -e GOOGLE_APPLICATION_CREDENTIALS="/tmp/keyfile.json" -e PROJECT=$GCP_PROJECT -i andreysenov/firebase-tools firebase database:get / --project "$GCP_PROJECT" | jq .

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating GCP Firebase Source connector"
playground connector create-or-update --connector firebase-source --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
     "connector.class" : "io.confluent.connect.firebase.FirebaseSourceConnector",
     "tasks.max" : "1",
     "gcp.firebase.credentials.path": "/tmp/keyfile.json",
     "gcp.firebase.database.reference": "https://$GCP_PROJECT.firebaseio.com/musicBlog",
     "gcp.firebase.snapshot":"true",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "errors.tolerance": "all",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF

sleep 10

log "Verify messages are in topic artists"
playground topic consume --topic artists --min-expected-messages 3 --timeout 60

log "Verify messages are in topic songs"
playground topic consume --topic songs --min-expected-messages 3 --timeout 60
