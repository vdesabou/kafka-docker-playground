#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

# generate an 8-character random suffix to make the resource names unique per run
UNIQUE_SUFFIX=$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)

GCP_SPANNER_INSTANCE="spanner-instance-$USER-$UNIQUE_SUFFIX"
GCP_SPANNER_DATABASE="spanner-db-$USER-$UNIQUE_SUFFIX"
GCP_SPANNER_REGION=${1:-europe-west2}

cd ../../ccloud/fm-gcp-spanner-sink
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

bootstrap_ccloud_environment "gcp" "$GCP_SPANNER_REGION"

set +e
playground topic delete --topic products
sleep 3
playground topic create --topic products --nb-partitions 1
set -e


log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

set +e
log "Deleting Database and Instance, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases delete $GCP_SPANNER_DATABASE --instance $GCP_SPANNER_INSTANCE --project $GCP_PROJECT << EOF
Y
EOF
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances delete $GCP_SPANNER_INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF
set -e
log "Create a Spanner Instance and Database"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances create $GCP_SPANNER_INSTANCE --project $GCP_PROJECT --config=regional-$GCP_SPANNER_REGION --description=playground-spanner-instance --nodes=1
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases create $GCP_SPANNER_DATABASE --instance $GCP_SPANNER_INSTANCE --project $GCP_PROJECT

function cleanup_cloud_resources {
  log "Deleting GCP Spanner database $GCP_SPANNER_DATABASE"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases delete $GCP_SPANNER_DATABASE --instance $GCP_SPANNER_INSTANCE --project $GCP_PROJECT << EOF
Y
EOF
  log "Deleting GCP Spanner instance $GCP_SPANNER_INSTANCE"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner instances delete $GCP_SPANNER_INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF
  docker rm -f gcloud-config
}
trap cleanup_cloud_resources EXIT

log "Sending messages to topic products"
playground topic produce -t products --nb-messages 2 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

playground topic produce -t products --nb-messages 1 --forced-value '{"name": "notebooks", "price": 1.99, "quantity": 5}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "price",
      "type": "float"
    },
    {
      "name": "quantity",
      "type": "int"
    }
  ]
}
EOF

connector_name="SpannerSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "SpannerSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "gcp.spanner.credentials.json" : "$GCP_KEYFILE_CONTENT",
  "auto.create" : "true",
  "table.name.format" : "kafka_\${topic}",
  "gcp.spanner.instance.id" : "$GCP_SPANNER_INSTANCE",
  "gcp.spanner.database.id" : "$GCP_SPANNER_DATABASE",
  "input.data.format": "AVRO",
  "auto.create": "true",
  "topics": "products",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 60

log "Verify data is in GCP Spanner"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud spanner databases execute-sql $GCP_SPANNER_DATABASE --instance $GCP_SPANNER_INSTANCE --project $GCP_PROJECT --sql='select * from kafka_products' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "notebooks" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name