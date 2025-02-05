#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

GCP_FUNCTION_REGION=${1:-europe-west2}
GCP_FUNCTION_FUNCTION=${2:-function-1}

cd ../../connect/connect-gcp-cloud-functions-sink
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


log "Produce test data to the functions-messages topic in Kafka"
playground topic produce -t functions-messages --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF

log "Creating Google Cloud Functions Sink connector"
playground connector create-or-update --connector gcp-functions  << EOF
{
    "connector.class": "io.confluent.connect.gcp.functions.GoogleCloudFunctionsSinkConnector",
    "tasks.max" : "1",
    "topics" : "functions-messages",
    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
    "value.converter":"org.apache.kafka.connect.storage.StringConverter",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor":1,
    "function.name": "$GCP_FUNCTION_FUNCTION",
    "project.id": "$GCP_PROJECT",
    "region": "$GCP_FUNCTION_REGION",
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
}
EOF

sleep 10

log "Confirm that the messages were delivered to the result topic in Kafka"
playground topic consume --topic test-result --min-expected-messages 3 --timeout 60
