#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../ccloud/fm-gcp-pubsub-source
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

bootstrap_ccloud_environment

GCP_PUB_SUB_TOPIC="topic-1-$GITHUB_RUN_NUMBER"
GCP_PUB_SUB_SUBSCRIPTION="subscription-1-$GITHUB_RUN_NUMBER"

set +e
playground topic delete --topic pubsub-topic
sleep 3
playground topic create --topic pubsub-topic --nb-partitions 1
set -e


log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json


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

connector_name="PubSubSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "PubSubSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "kafka.topic" : "pubsub-topic",
    "gcp.pubsub.credentials.json" : "$GCP_KEYFILE_CONTENT",
    "gcp.pubsub.project.id" : "$GCP_PROJECT",
    "gcp.pubsub.topic.id" : "$GCP_PUB_SUB_TOPIC",
    "gcp.pubsub.subscription.id" : "$GCP_PUB_SUB_SUBSCRIPTION",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify messages are in topic pubsub-topic"
playground topic consume --topic pubsub-topic --min-expected-messages 3 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name