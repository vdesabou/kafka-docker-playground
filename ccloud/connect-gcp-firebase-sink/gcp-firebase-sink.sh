#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

GCP_KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "ERROR: either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
     exit 1
else 
    if [ -f ${GCP_KEYFILE} ]
    then
        GCP_KEYFILE_CONTENT=$(cat keyfile.json | jq -aRs . | sed 's/^"//' | sed 's/"$//')
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi

log "Removing all data"
docker run -v $PWD/../../ccloud/connect-gcp-firebase-sink/keyfile.json:/tmp/keyfile.json -e GOOGLE_APPLICATION_CREDENTIALS="/tmp/keyfile.json" -e PROJECT=$GCP_PROJECT -i andreysenov/firebase-tools firebase database:remove / --project "$GCP_PROJECT" --force

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.yml"


#############

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic create --topic artists
playground topic create --topic songs
set -e

log "Creating GCP Firebase Sink connector"
playground connector create-or-update --connector firebase-sink  << EOF
{
  "connector.class" : "io.confluent.connect.firebase.FirebaseSinkConnector",
  "tasks.max" : "1",
  "topics":"artists,songs",
  "gcp.firebase.credentials.path": "/tmp/keyfile.json",
  "gcp.firebase.database.reference": "https://$GCP_PROJECT.firebaseio.com/musicBlog",
  "insert.mode":"update",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter" : "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "$SCHEMA_REGISTRY_URL",
  "value.converter.basic.auth.user.info": "\${file:/data:schema.registry.basic.auth.user.info}",
  "value.converter.basic.auth.credentials.source": "USER_INFO",
  "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
  "confluent.topic.sasl.mechanism" : "PLAIN",
  "confluent.topic.bootstrap.servers": "\${file:/data:bootstrap.servers}",
  "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
  "confluent.topic.security.protocol" : "SASL_SSL",
  "confluent.topic.replication.factor": "3"
}
EOF


log "Produce Avro data to topic artists"
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
docker run -v $PWD/../../ccloud/connect-gcp-firebase-sink/keyfile.json:/tmp/keyfile.json -e GOOGLE_APPLICATION_CREDENTIALS="/tmp/keyfile.json" -e PROJECT=$GCP_PROJECT -i andreysenov/firebase-tools firebase database:get / --project "$GCP_PROJECT" | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "artist" /tmp/result.log
