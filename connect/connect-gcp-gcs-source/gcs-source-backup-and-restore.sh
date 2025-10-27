#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.6.15"
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
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.backup-and-restore.yml"

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${GITHUB_RUN_NUMBER}${TAG_BASE}
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}
GCS_BUCKET_REGION=${1:-europe-west2}

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


##########################
## SINK
##########################

log "Sending messages to topic gcs_topic"
playground topic produce -t gcs_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
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


log "Creating GCS Sink connector"
playground connector create-or-update --connector GCSSinkConnector  << EOF
{
  "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
  "tasks.max" : "1",
  "topics" : "gcs_topic",
  "gcs.bucket.name" : "$GCS_BUCKET_NAME",
  "gcs.part.size": "5242880",
  "flush.size": "3",
  "gcs.credentials.path": "/tmp/keyfile.json",
  "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
  "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
  "schema.compatibility": "NONE",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1",
  "errors.tolerance": "all",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true"
}
EOF

sleep 10

log "Listing objects of in GCS"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud storage ls gs://$GCS_BUCKET_NAME/topics/gcs_topic/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -i --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gcloud storage cp gs://$GCS_BUCKET_NAME/topics/gcs_topic/partition=0/gcs_topic+0+0000000000.avro /tmp/gcs_topic+0+0000000000.avro

playground  tools read-avro-file --file /tmp/gcs_topic+0+0000000000.avro

docker rm -f gcloud-config

##########################
## SOURCE
##########################
log "Creating Backup and Restore GCS Source connector"
playground connector create-or-update --connector gcs-source  << EOF
{
	"connector.class": "io.confluent.connect.gcs.GcsSourceConnector",
	"gcs.bucket.name" : "$GCS_BUCKET_NAME",
	"gcs.credentials.path" : "/tmp/keyfile.json",
	"format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
	"tasks.max" : "1",
	"confluent.topic.bootstrap.servers" : "broker:9092",
	"confluent.topic.replication.factor" : "1",
	"transforms" : "AddPrefix",
	"transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
	"transforms.AddPrefix.regex" : ".*",
	"transforms.AddPrefix.replacement" : "copy_of_\$0"
}
EOF

sleep 10

log "Verify messages are in topic copy_of_gcs_topic"
playground topic consume --topic copy_of_gcs_topic --min-expected-messages 9 --timeout 60
