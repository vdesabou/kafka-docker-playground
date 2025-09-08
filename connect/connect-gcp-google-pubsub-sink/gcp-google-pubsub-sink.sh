#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-google-pubsub-sink

if [ ! -f ${DIR}/pubsub-group-kafka-connector-1.3.2.jar ]
then
     wget -q https://repo1.maven.org/maven2/com/google/cloud/pubsub-group-kafka-connector/1.3.2/pubsub-group-kafka-connector-1.3.2.jar
fi

if [ ! -f ${DIR}/grpc-netty-1.70.0.jar ]
then
     wget -q https://repo1.maven.org/maven2/io/grpc/grpc-netty/1.70.0/grpc-netty-1.70.0.jar
fi

if [ ! -f ${DIR}/grpc-rls-1.70.0.jar ]
then
     wget -q https://repo1.maven.org/maven2/io/grpc/grpc-rls/1.70.0/grpc-rls-1.70.0.jar
fi

GCP_KEYFILE="${PWD}/keyfile.json"
if [ ! -f ${GCP_KEYFILE} ] && [ -z "$GCP_KEYFILE_CONTENT" ]
then
     logerror "❌ either the file ${GCP_KEYFILE} is not present or environment variable GCP_KEYFILE_CONTENT is not set!"
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
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

GCP_PUB_SUB_TOPIC="topic-1-$GITHUB_RUN_NUMBER"
GCP_PUB_SUB_SUBSCRIPTION="subscription-1-$GITHUB_RUN_NUMBER"

# cleanup if required
set +e
log "Delete topic $GCP_PUB_SUB_TOPIC and subscription $GCP_PUB_SUB_SUBSCRIPTION, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete $GCP_PUB_SUB_TOPIC
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete $GCP_PUB_SUB_SUBSCRIPTION
set -e

log "Create a Pub/Sub topic called $GCP_PUB_SUB_TOPIC"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics create $GCP_PUB_SUB_TOPIC --labels=cflt_managed_by=user,cflt_managed_id="$USER"

log "Create a Pub/Sub subscription called $GCP_PUB_SUB_SUBSCRIPTION"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions create --topic $GCP_PUB_SUB_TOPIC $GCP_PUB_SUB_SUBSCRIPTION

function cleanup_cloud_resources {
    set +e
    log "Delete GCP PubSub topic $GCP_PUB_SUB_TOPIC and subscription $GCP_PUB_SUB_SUBSCRIPTION"
    check_if_continue
    docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete $GCP_PUB_SUB_TOPIC
    docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete $GCP_PUB_SUB_SUBSCRIPTION

    docker rm -f gcloud-config
}
trap cleanup_cloud_resources EXIT

log "send data to pubsub-topic topic"
playground topic produce -t pubsub-topic --nb-messages 3 --key "key1" << 'EOF'
{
  "fields": [
    {
      "name": "u_name",
      "type": "string"
    },
    {
      "name": "u_price",
      "type": "float"
    },
    {
      "name": "u_quantity",
      "type": "int"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

sleep 10

log "Creating Google Cloud Pub/Sub Group Kafka Sink connector"
playground connector create-or-update --connector pubsub-sink  << EOF
{
     "connector.class" : "com.google.pubsub.kafka.sink.CloudPubSubSinkConnector",
     "tasks.max" : "1",
     "topics" : "pubsub-topic",
     "cps.project" : "$GCP_PROJECT",
     "cps.topic" : "$GCP_PUB_SUB_TOPIC",
     "gcp.credentials.file.path" : "/tmp/keyfile.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
     "metadata.publish": "true",
     "headers.publish": "true"
}
EOF

sleep 120

log "Get messages from $GCP_PUB_SUB_TOPIC"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions pull $GCP_PUB_SUB_SUBSCRIPTION > /tmp/result.log  2>&1
cat /tmp/result.log
grep "MESSAGE_ID" /tmp/result.log