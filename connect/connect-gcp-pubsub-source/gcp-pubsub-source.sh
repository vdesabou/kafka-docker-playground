#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.2.9"
then
     logwarn "minimal supported connector version is 1.2.10 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-pubsub-source
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
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions create --topic $GCP_PUB_SUB_TOPIC $GCP_PUB_SUB_SUBSCRIPTION --ack-deadline 60 --labels=cflt_managed_by=user,cflt_managed_id="$USER"

function cleanup_cloud_resources {
    set +e
    log "Delete GCP PubSub topic $GCP_PUB_SUB_TOPIC and subscription $GCP_PUB_SUB_SUBSCRIPTION"
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

log "Creating GCP PubSub Source connector"
playground connector create-or-update --connector pubsub-source  << EOF
{
    "connector.class" : "io.confluent.connect.gcp.pubsub.PubSubSourceConnector",
    "tasks.max" : "1",
    "kafka.topic" : "pubsub-topic",
    "gcp.pubsub.project.id" : "$GCP_PROJECT",
    "gcp.pubsub.topic.id" : "$GCP_PUB_SUB_TOPIC",
    "gcp.pubsub.subscription.id" : "$GCP_PUB_SUB_SUBSCRIPTION",
    "gcp.pubsub.credentials.path" : "/tmp/keyfile.json",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 10

log "Verify messages are in topic pubsub-topic"
playground topic consume --topic pubsub-topic --min-expected-messages 3 --timeout 60


log "Verify acknowledgement by checking for duplicate messages"
messages=$(playground topic consume --topic pubsub-topic --min-expected-messages 3 --timeout 60 --max-messages 5000)

# Extract message data and count occurrences
message_count=$(echo "$messages" | grep -o "Peter\|Megan\|Erin" | wc -l | tr -d ' ')
unique_count=$(echo "$messages" | grep -o "Peter\|Megan\|Erin" | sort -u | wc -l | tr -d ' ')

if [ "$message_count" -eq 3 ] && [ "$unique_count" -eq 3 ]
then
    log "✅ Acknowledgement verified: received exactly 3 unique messages (Peter, Megan, Erin) - no duplicates"
else
    logerror "❌ Message mismatch — potential commit/ACK failure. Found $message_count total messages, $unique_count unique (expected 3 unique)"
    exit 1
fi
