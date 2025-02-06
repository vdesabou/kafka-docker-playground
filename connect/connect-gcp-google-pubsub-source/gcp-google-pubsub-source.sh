#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-google-pubsub-source

if [ ! -f ${DIR}/pubsub-group-kafka-connector-1.2.0.jar ]
then
     wget -q https://repo1.maven.org/maven2/com/google/cloud/pubsub-group-kafka-connector/1.2.0/pubsub-group-kafka-connector-1.2.0.jar
fi

if [ ! -f ${DIR}/grpc-netty-1.54.0.jar ]
then
     wget -q https://repo1.maven.org/maven2/io/grpc/grpc-netty/1.54.0/grpc-netty-1.54.0.jar
fi

if [ ! -f ${DIR}/grpc-rls-1.55.3.jar ]
then
     wget -q https://repo1.maven.org/maven2/io/grpc/grpc-rls/1.55.3/grpc-rls-1.55.3.jar
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
log "Delete topic and subscription, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete $GCP_PUB_SUB_TOPIC
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete $GCP_PUB_SUB_SUBSCRIPTION
set -e

log "Create a Pub/Sub topic called $GCP_PUB_SUB_TOPIC"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics create $GCP_PUB_SUB_TOPIC

log "Create a Pub/Sub subscription called $GCP_PUB_SUB_SUBSCRIPTION"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions create --topic $GCP_PUB_SUB_TOPIC $GCP_PUB_SUB_SUBSCRIPTION --ack-deadline 60

function cleanup_cloud_resources {
    set +e
    log "Delete GCP PubSub topic and subscription"
    check_if_continue
    docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete $GCP_PUB_SUB_TOPIC
    docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete $GCP_PUB_SUB_SUBSCRIPTION

    docker rm -f gcloud-config
}
trap cleanup_cloud_resources EXIT

log "Publish three messages to $GCP_PUB_SUB_TOPIC"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics publish $GCP_PUB_SUB_TOPIC --message "Peter"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics publish $GCP_PUB_SUB_TOPIC --message "Megan"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics publish $GCP_PUB_SUB_TOPIC --message "Erin"

sleep 10

log "Creating Google Cloud Pub/Sub Group Kafka Source connector"
playground connector create-or-update --connector pubsub-source  << EOF
{
     "connector.class" : "com.google.pubsub.kafka.source.CloudPubSubSourceConnector",
     "tasks.max" : "1",
     "kafka.topic" : "pubsub-topic",
     "cps.project" : "$GCP_PROJECT",
     "cps.topic" : "$GCP_PUB_SUB_TOPIC",
     "cps.subscription" : "$GCP_PUB_SUB_SUBSCRIPTION",
     "gcp.credentials.file.path" : "/tmp/keyfile.json",
     "errors.tolerance": "all",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF

sleep 20

log "Verify messages are in topic pubsub-topic"
playground topic consume --topic pubsub-topic --min-expected-messages 1 --timeout 60