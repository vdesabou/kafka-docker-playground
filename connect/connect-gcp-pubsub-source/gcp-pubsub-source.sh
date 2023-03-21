#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-pubsub-source
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

log "Creating GCP PubSub Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.gcp.pubsub.PubSubSourceConnector",
               "tasks.max" : "1",
               "kafka.topic" : "pubsub-topic",
               "gcp.pubsub.project.id" : "'"$GCP_PROJECT"'",
               "gcp.pubsub.topic.id" : "topic-1",
               "gcp.pubsub.subscription.id" : "subscription-1",
               "gcp.pubsub.credentials.path" : "/tmp/keyfile.json",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/pubsub-source/config | jq .

sleep 10

log "Verify messages are in topic pubsub-topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic pubsub-topic --from-beginning --max-messages 3

log "Delete topic and subscription"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} topics delete topic-1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${GCP_PROJECT} subscriptions delete subscription-1

docker rm -f gcloud-config