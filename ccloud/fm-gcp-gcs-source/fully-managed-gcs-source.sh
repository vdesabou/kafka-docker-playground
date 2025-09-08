#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../ccloud/fm-gcp-gcs-source
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

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}
GCS_BUCKET_REGION=${1:-europe-west2}

bootstrap_ccloud_environment "gcp" "$GCS_BUCKET_REGION"

set +e
playground topic delete --topic quick-start-topic
sleep 3
playground topic create --topic quick-start-topic --nb-partitions 1
set -e

log "Doing gcloud authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage buckets create gs://$GCS_BUCKET_NAME --project=$(cat ${GCP_KEYFILE} | jq -r .project_id) --location=$GCS_BUCKET_REGION
set -e

log "Setting labels on bucket <$GCS_BUCKET_NAME>"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage buckets update gs://$GCS_BUCKET_NAME --update-labels=cflt_managed_by=user,cflt_managed_id="$USER"

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage rm gs://$GCS_BUCKET_NAME/topics/gcs_topic/** --recursive
set -e

log "Copy generalized.quickstart.json to bucket $GCS_BUCKET_NAME/quickstart"
docker run -i -v ${PWD}:/tmp/ --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage cp /tmp/generalized.quickstart.json gs://$GCS_BUCKET_NAME/quickstart/generalized.quickstart.json

connector_name="GcsSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "GcsSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics.dir": "quickstart",
    "topic.regex.list": "quick-start-topic:.*",
    "gcs.credentials.json" : "$GCP_KEYFILE_CONTENT",
    "gcs.bucket.name" : "$GCS_BUCKET_NAME",
    "input.data.format": "JSON",
    "output.data.format": "JSON",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify messages are in topic quick-start-topic"
playground topic consume --topic quick-start-topic --min-expected-messages 9 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

docker rm -f gcloud-config