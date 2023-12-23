#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-firebase-sink
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
docker run -v $PWD/../../connect/connect-gcp-firebase-sink/keyfile.json:/tmp/keyfile.json -e GOOGLE_APPLICATION_CREDENTIALS="/tmp/keyfile.json" -e PROJECT=$GCP_PROJECT -i andreysenov/firebase-tools firebase database:remove / --project "$GCP_PROJECT" --force

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating GCP Firebase Sink connector"
playground connector create-or-update --connector firebase-sink --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
     "connector.class" : "io.confluent.connect.firebase.FirebaseSinkConnector",
     "tasks.max" : "1",
     "topics":"artists,songs",
     "gcp.firebase.credentials.path": "/tmp/keyfile.json",
     "gcp.firebase.database.reference": "https://$GCP_PROJECT.firebaseio.com/musicBlog",
     "insert.mode":"update",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter" : "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1"
}
EOF


playground topic produce -t artists --nb-messages 4 --key "artistId%g" << 'EOF'
{
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "genre",
      "type": "string"
    }
  ],
  "name": "artists",
  "type": "record"
}
EOF

log "Produce Avro data to topic songs"
playground topic produce -t songs --nb-messages 3 --key "songId%g" << 'EOF'
{
  "fields": [
    {
      "name": "title",
      "type": "string"
    },
    {
      "name": "artist",
      "type": "string"
    }
  ],
  "name": "songs",
  "type": "record"
}
EOF

log "Verifying data is in Firebase"
docker run -v $PWD/../../connect/connect-gcp-firebase-sink/keyfile.json:/tmp/keyfile.json -e GOOGLE_APPLICATION_CREDENTIALS="/tmp/keyfile.json" -e PROJECT=$GCP_PROJECT -i andreysenov/firebase-tools firebase database:get / --project "$GCP_PROJECT" | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "artist" /tmp/result.log
