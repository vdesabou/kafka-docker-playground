#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

GCP_KEYFILE="${DIR}/keyfile.json"
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

bootstrap_ccloud_environment

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG}
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" rm -r -f -d "$DATASET"
sleep 1
# https://github.com/GoogleCloudPlatform/terraform-google-secured-data-warehouse/issues/35
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $GCP_PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" mk --dataset --description "used by playground" "$DATASET"

log "Creating bqtopic topic in Confluent Cloud"
set +e
create_topic bqtopic
set -e

log "Sending messages to topic bqtopic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker run -i --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG}  kafka-avro-console-producer --broker-list $BOOTSTRAP_SERVERS --producer-property ssl.endpoint.identification.algorithm=https --producer-property sasl.mechanism=PLAIN --producer-property security.protocol=SASL_SSL --producer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --topic bqtopic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

cat << EOF > connector.json
{
     "connector.class": "BigQuerySink",
     "name": "BigQuerySink",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "topics": "bqtopic",
     "keyfile" : $GCP_KEYFILE_CONTENT,
     "project" : "$GCP_PROJECT",
     "datasets" : "$DATASET",
     "input.data.format" : "AVRO",
     "auto.create.tables" : "true",
     "sanitize.topics" : "true",
     "auto.update.schemas" : "true",
     "sanitize.field.names" : "true",
     "allow.schema.unionization" :"true",
     "tasks.max" : "1"
}
EOF

log "Connector configuration is:"
cat connector.json

set +e
log "Deleting fully managed connector, it might fail..."
delete_ccloud_connector connector.json
set -e

log "Creating fully managed connector"
create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300

log "Sleeping 120 seconds"
sleep 120

log "Verify data is in GCP BigQuery:"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" query "SELECT * FROM $DATASET.bqtopic;" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "value1" /tmp/result.log

log "Do you want to delete the fully managed connector ?"
check_if_continue

log "Deleting fully managed connector"
delete_ccloud_connector connector.json

log "Drop dataset $DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" rm -r -f -d "$DATASET"

docker rm -f gcloud-config