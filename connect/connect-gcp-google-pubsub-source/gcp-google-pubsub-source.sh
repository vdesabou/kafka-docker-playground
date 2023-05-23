#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -f ${DIR}/pubsub-group-kafka-connector-1.0.0.jar ]
then
     wget https://repo1.maven.org/maven2/com/google/cloud/pubsub-group-kafka-connector/1.0.0/pubsub-group-kafka-connector-1.0.0.jar
fi

cd ../../connect/connect-gcp-google-pubsub-source
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json


# cleanup if required
set +e
log "Delete topic and subscription, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete topic-1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete subscription-1
set -e

log "Create a Pub/Sub topic called topic-1"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics create topic-1

log "Create a Pub/Sub subscription called subscription-1"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions create --topic topic-1 subscription-1

log "Publish three messages to topic-1"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics publish topic-1 --message "Peter"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics publish topic-1 --message "Megan"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics publish topic-1 --message "Erin"

sleep 10

log "Creating Google Cloud Pub/Sub Group Kafka Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "com.google.pubsub.kafka.source.CloudPubSubSourceConnector",
               "tasks.max" : "1",
               "kafka.topic" : "pubsub-topic",
               "cps.project" : "'"$GCP_PROJECT"'",
               "cps.topic" : "topic-1",
               "cps.subscription" : "subscription-1",
               "gcp.credentials.file.path" : "/tmp/keyfile.json",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/pubsub-source/config | jq .

sleep 10

log "Verify messages are in topic pubsub-topic"
playground topic consume --topic pubsub-topic --min-expected-messages 3

log "Delete topic and subscription"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete topic-1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete subscription-1

docker rm -f gcloud-config