#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi
REGION=${2:-us-central1}
FUNCTION=${3:-function-1}

cd ../../connect/connect-gcp-cloud-functions-sink
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


log "Produce test data to the functions-messages topic in Kafka"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic functions-messages --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF

log "Creating Google Cloud Functions Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcp.functions.GoogleCloudFunctionsSinkConnector",
               "tasks.max" : "1",
               "topics" : "functions-messages",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor":1,
               "function.name": "'"$FUNCTION"'",
               "project.id": "'"$GCP_PROJECT"'",
               "region": "'"$REGION"'",
               "gcf.credentials.path": "/tmp/keyfile.json",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "test-error",
               "reporter.error.topic.replication.factor": 1,
               "reporter.error.topic.key.format": "string",
               "reporter.error.topic.value.format": "string",
               "reporter.result.topic.name": "test-result",
               "reporter.result.topic.key.format": "string",
               "reporter.result.topic.value.format": "string",
               "reporter.result.topic.replication.factor": 1
          }' \
     http://localhost:8083/connectors/gcp-functions/config | jq .

sleep 10

log "Confirm that the messages were delivered to the result topic in Kafka"
playground topic consume --topic test-result --min-expected-messages 3
