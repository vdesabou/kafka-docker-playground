#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../ccloud/fm-gcp-gcs-sink
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
playground topic delete --topic gcs_topic
sleep 3
playground topic create --topic gcs_topic --nb-partitions 1
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

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage rm gs://$GCS_BUCKET_NAME/topics/gcs_topic/** --recursive
set -e

log "Sending messages to topic gcs_topic"
playground topic produce -t gcs_topic --nb-messages 1000 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

connector_name="GcsSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "GcsSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "gcs_topic",
  "gcs.credentials.config" : "$GCP_KEYFILE_CONTENT",
  "gcs.bucket.name" : "$GCS_BUCKET_NAME",
  "input.data.format" : "AVRO",
  "output.data.format" : "AVRO",
  "time.interval" : "HOURLY",
  "flush.size": "1000",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


sleep 10

log "Listing objects of in GCS"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage ls gs://$GCS_BUCKET_NAME/topics/gcs_topic/** --recursive

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -i --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gcloud storage cp gs://$GCS_BUCKET_NAME/topics/gcs_topic/*/*/*/*/gcs_topic+0+0000000000.avro /tmp/gcs_topic+0+0000000000.avro

playground  tools read-avro-file --file /tmp/gcs_topic+0+0000000000.avro

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name

docker rm -f gcloud-config