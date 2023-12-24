#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: This RBAC example is working starting from CP 5.4 only"
    exit 111
fi

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../connect/connect-gcp-gcs-sink
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

playground start-environment --environment rbac-sasl-plain --docker-compose-override-file "${PWD}/docker-compose.yml"

GCS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
GCS_BUCKET_NAME=${GCS_BUCKET_NAME//[-.]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

log "Creating bucket name <$GCS_BUCKET_NAME>, if required"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil mb -p $(cat ${GCP_KEYFILE} | jq -r .project_id) gs://$GCS_BUCKET_NAME
set -e

log "Removing existing objects in GCS, if applicable"
set +e
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil -m rm -r gs://$GCS_BUCKET_NAME/topics/rbac_gcs_topic
set -e


log "Sending messages to topic rbac_gcs_topic"
playground topic produce -t rbac_gcs_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Checking messages from topic rbac_gcs_topic"
playground topic consume --topic rbac_gcs_topic --min-expected-messages 1 --timeout 60

log "Creating GCS Sink connector"
playground connector create-or-update --connector my-rbac-connector  << EOF
{
    "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
    "tasks.max" : "1",
    "topics" : "rbac_gcs_topic",
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
    "confluent.topic.sasl.mechanism": "PLAIN",
    "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"admin\" password=\"admin-secret\";",
    "confluent.topic.security.protocol" : "SASL_PLAINTEXT",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter.basic.auth.credentials.source": "USER_INFO",
    "value.converter.basic.auth.user.info": "connectorSA:connectorSA",
    "consumer.override.sasl.jaas.config": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required username=\"connectorSA\" password=\"connectorSA\" metadataServerUrls=\"http://broker:8091\";"
}
EOF

sleep 10

log "Listing objects of in GCS"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gsutil ls gs://$GCS_BUCKET_NAME/topics/rbac_gcs_topic/partition=0/

log "Getting one of the avro files locally and displaying content with avro-tools"
docker run -i --volumes-from gcloud-config -v /tmp:/tmp/ google/cloud-sdk:latest gsutil cp gs://$GCS_BUCKET_NAME/topics/rbac_gcs_topic/partition=0/rbac_gcs_topic+0+0000000000.avro /tmp/rbac_gcs_topic+0+0000000000.avro

docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/rbac_gcs_topic+0+0000000000.avro

docker rm -f gcloud-config