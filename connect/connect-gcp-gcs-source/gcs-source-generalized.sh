#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $CONNECTOR_TAG "2.0.99"; then
    # skipped
    logwarn "WARN: skipped as it requires connector version 2.1.0"
    exit 111
fi

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "2.6.15"
then
     logwarn "minimal supported connector version is 2.6.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-gcs-source
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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.generalized.yml"

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}
GCS_BUCKET_REGION=${1:-europe-west2}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil mb -p $(cat ${GCP_KEYFILE} | jq -r .project_id) -l $GCS_BUCKET_REGION gs://$GCS_BUCKET_NAME
set -e

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/*
set -e

log "Copy generalized.quickstart.json to bucket $GCS_BUCKET_NAME/quickstart"
docker run -i -v ${PWD}:/tmp/ --volumes-from gcloud-config google/cloud-sdk:latest gsutil cp /tmp/generalized.quickstart.json gs://$GCS_BUCKET_NAME/quickstart/generalized.quickstart.json

log "Creating Generalized GCS Source connector"
playground connector create-or-update --connector gcs-source  << EOF
{
    "connector.class": "io.confluent.connect.gcs.GcsSourceConnector",
    "gcs.bucket.name" : "$GCS_BUCKET_NAME",
    "gcs.credentials.path" : "/tmp/keyfile.json",
    "format.class": "io.confluent.connect.gcs.format.json.JsonFormat",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "mode": "GENERIC",
    "topics.dir": "quickstart",
    "topic.regex.list": "quick-start-topic:.*",
    "tasks.max" : "1",
    "confluent.topic.bootstrap.servers" : "broker:9092",
    "confluent.topic.replication.factor" : "1",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 10

log "Verify messages are in topic quick-start-topic"
playground topic consume --topic quick-start-topic --min-expected-messages 9 --timeout 60

# null    {"f1":"value1"}
# null    {"f1":"value2"}
# null    {"f1":"value3"}
# null    {"f1":"value4"}
# null    {"f1":"value5"}
# null    {"f1":"value6"}
# null    {"f1":"value7"}
# null    {"f1":"value8"}
# null    {"f1":"value9"}
