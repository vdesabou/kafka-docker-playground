#!/bin/bash
set -e

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "gcloud"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     echo "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Doing gsutil authentication"
gcloud auth activate-service-account --key-file ${KEYFILE}


# cleanup if required
set +e
echo "Delete topic and subscription, if required"
gcloud pubsub topics delete topic-1
gcloud pubsub subscriptions delete subscription-1
set - e

echo "Create a Pub/Sub topic called topic-1"
gcloud pubsub topics create topic-1

echo "Create a Pub/Sub subscription called subscription-1"
gcloud pubsub subscriptions create --topic topic-1 subscription-1

echo "Publish three messages to topic-1"
gcloud pubsub topics publish topic-1 --message "Peter"
gcloud pubsub topics publish topic-1 --message "Megan"
gcloud pubsub topics publish topic-1 --message "Erin"

sleep 10

echo "Creating GCP PubSub Source connector"
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
     http://localhost:8083/connectors/pubsub-source/config | jq .

sleep 10

echo "Verify messages are in topic pubsub-topic"
docker exec schema-registry kafka-avro-console-consumer -bootstrap-server broker:9092 --topic pubsub-topic --from-beginning --max-messages 3

echo "Delete topic and subscription"
gcloud pubsub topics delete topic-1
gcloud pubsub subscriptions delete subscription-1