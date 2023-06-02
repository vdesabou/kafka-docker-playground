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

if [ ! -z "$CI" ]
then
     # running with github actions

     
     # if this is github actions
     log "Removing all data"
     docker run -p 9005:9005 -e FIREBASE_TOKEN="$FIREBASE_TOKEN" -e PROJECT=$GCP_PROJECT -i kamshak/firebase-tools-docker firebase database:remove / -y --token "$FIREBASE_TOKEN" --project "$GCP_PROJECT"
fi


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating GCP Firebase Sink connector"
playground connector create-or-update --connector firebase-sink << EOF
{
               "connector.class" : "io.confluent.connect.firebase.FirebaseSinkConnector",
               "tasks.max" : "1",
               "topics":"artists,songs",
               "gcp.firebase.credentials.path": "/tmp/keyfile.json",
               "gcp.firebase.database.reference": "https://'"$GCP_PROJECT"'.firebaseio.com/musicBlog",
               "insert.mode":"update",
               "key.converter" : "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url":"http://schema-registry:8081",
               "value.converter" : "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }
EOF


log "Produce Avro data to topic artists"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic artists --property parse.key=true --property key.schema='{"type":"string"}' --property "key.separator=:" --property value.schema='{"type":"record","name":"artists","fields":[{"name":"name","type":"string"},{"name":"genre","type":"string"}]}' << EOF
"artistId1":{"name":"Michael Jackson","genre":"Pop"}
"artistId2":{"name":"Bob Dylan","genre":"American folk"}
"artistId3":{"name":"Freddie Mercury","genre":"Rock"}
EOF

log "Produce Avro data to topic songs"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic songs --property parse.key=true --property key.schema='{"type":"string"}' --property "key.separator=:" --property value.schema='{"type":"record","name":"songs","fields":[{"name":"title","type":"string"},{"name":"artist","type":"string"}]}' << EOF
"songId1":{"title":"billie jean","artist":"Michael Jackson"}
"songId2":{"title":"hurricane","artist":"Bob Dylan"}
"songId3":{"title":"bohemian rhapsody","artist":"Freddie Mercury"}
EOF

log "Follow README to verify data is in Firebase"

if [ ! -z "$CI" ]
then
     # if this is github actions
     log "Verifying data is in Firebase"
     docker run -p 9005:9005 -e FIREBASE_TOKEN=$FIREBASE_TOKEN -e PROJECT=$GCP_PROJECT -i kamshak/firebase-tools-docker firebase database:get / --token "$FIREBASE_TOKEN" --project "$GCP_PROJECT" | jq . > /tmp/result.log  2>&1
     cat /tmp/result.log
     grep "Michael Jackson" /tmp/result.log
fi

