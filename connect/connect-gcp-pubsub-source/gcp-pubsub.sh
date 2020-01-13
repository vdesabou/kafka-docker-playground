#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     log "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
docker run -ti -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --key-file /tmp/keyfile.json
set -e


# cleanup if required
set +e
log "Delete topic and subscription, if required"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} topics delete topic-1
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} subscriptions delete subscription-1
set - e

log "Create a Pub/Sub topic called topic-1"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} topics create topic-1

log "Create a Pub/Sub subscription called subscription-1"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} subscriptions create --topic topic-1 subscription-1

log "Publish three messages to topic-1"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} topics publish topic-1 --message "Peter"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} topics publish topic-1 --message "Megan"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} topics publish topic-1 --message "Erin"

sleep 10

log "Creating GCP PubSub Source connector"
docker exec -e PROJECT="$PROJECT" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.gcp.pubsub.PubSubSourceConnector",
                    "tasks.max" : "1",
                    "kafka.topic" : "pubsub-topic",
                    "gcp.pubsub.project.id" : "'"$PROJECT"'",
                    "gcp.pubsub.topic.id" : "topic-1",
                    "gcp.pubsub.subscription.id" : "subscription-1",
                    "gcp.pubsub.credentials.path" : "/root/keyfiles/keyfile.json",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/pubsub-source/config | jq_docker_cli .

sleep 10

log "Verify messages are in topic pubsub-topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic pubsub-topic --from-beginning --max-messages 3

log "Delete topic and subscription"
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} topics delete topic-1
docker run -ti --volumes-from gcloud-config google/cloud-sdk:latest gcloud pubsub --project ${PROJECT} subscriptions delete subscription-1

docker rm -f gcloud-config