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
        GCP_KEYFILE_CONTENT=`cat keyfile.json | jq -aRs .`
    else
        log "Creating ${GCP_KEYFILE} based on environment variable GCP_KEYFILE_CONTENT"
        echo -e "$GCP_KEYFILE_CONTENT" | sed 's/\\"/"/g' > ${GCP_KEYFILE}
    fi
fi

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
create_topic artists
create_topic songs
set -e

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
               "key.converter.schema.registry.url": "$SCHEMA_REGISTRY_URL",
               "key.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "key.converter.basic.auth.credentials.source": "USER_INFO",
               "value.converter" : "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "$SCHEMA_REGISTRY_URL",
               "value.converter.basic.auth.user.info": "${file:/data:schema.registry.basic.auth.user.info}",
               "value.converter.basic.auth.credentials.source": "USER_INFO",
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${file:/data:sasl.username}\" password=\"${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3"
          }
EOF


log "Produce Avro data to topic artists"
docker exec -i -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic artists --property parse.key=true --property key.schema='{"type":"string"}' --property "key.separator=:" --property value.schema='{"type":"record","name":"artists","fields":[{"name":"name","type":"string"},{"name":"genre","type":"string"}]}' << EOF
"artistId1":{"name":"Michael Jackson","genre":"Pop"}
"artistId2":{"name":"Bob Dylan","genre":"American folk"}
"artistId3":{"name":"Freddie Mercury","genre":"Rock"}
"artistId4":{"name":"Vincent McMorrow","genre":"Other"}
EOF

log "Produce Avro data to topic songs"
docker exec -i -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" connect kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic songs --property parse.key=true --property key.schema='{"type":"string"}' --property "key.separator=:" --property value.schema='{"type":"record","name":"songs","fields":[{"name":"title","type":"string"},{"name":"artist","type":"string"}]}' << EOF
"songId1":{"title":"billie jean","artist":"Michael Jackson"}
"songId2":{"title":"hurricane","artist":"Bob Dylan"}
"songId3":{"title":"bohemian rhapsody","artist":"Freddie Mercury"}
EOF

log "Follow README to verify data is in Firebase"

if [ ! -z "$CI" ]
then
     

     
     log "Verifying data is in Firebase"
     docker run -p 9005:9005 -e FIREBASE_TOKEN=$FIREBASE_TOKEN -e PROJECT=$GCP_PROJECT -i kamshak/firebase-tools-docker firebase database:get / --token "$FIREBASE_TOKEN" --project "$GCP_PROJECT" | jq . > /tmp/result.log  2>&1
     cat /tmp/result.log
     grep "Michael Jackson" /tmp/result.log
fi
