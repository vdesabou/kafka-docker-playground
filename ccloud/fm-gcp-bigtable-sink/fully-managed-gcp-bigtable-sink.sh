#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

GCP_BIGTABLE_REGION=${1:-europe-west2-a}
GCP_BIGTABLE_INSTANCE="pg${USER}fmbg${GITHUB_RUN_NUMBER}${TAG_BASE}"
GCP_BIGTABLE_INSTANCE=${GCP_BIGTABLE_INSTANCE//[-.]/}

cd ../../ccloud/fm-gcp-bigtable-sink
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

bootstrap_ccloud_environment

log "Creating big_query_cloud_stats topic"
set +e
playground topic delete --topic big_query_cloud_stats
sleep 3
playground topic create --topic big_query_cloud_stats
set -e

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

set +e
log "Deleting instance, if required"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $GCP_BIGTABLE_INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF
set -e
log "Create a BigTable Instance and Database"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances create $GCP_BIGTABLE_INSTANCE --project $GCP_PROJECT --cluster-config=id=$GCP_BIGTABLE_INSTANCE,zone=$GCP_BIGTABLE_REGION --display-name="playground-bigtable-instance"


function cleanup_cloud_resources {
  log "Delete GCP BigTable table kafka_big_query_cloud_stats"
  check_if_continue
  docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $GCP_PROJECT -instance $GCP_BIGTABLE_INSTANCE deletetable kafka_big_query_cloud_stats

  log "Delete GCP BigTable instance $GCP_BIGTABLE_INSTANCE"
  check_if_continue
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $GCP_BIGTABLE_INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF

  docker rm -f gcloud-config
}
trap cleanup_cloud_resources EXIT


log "Sending messages to topic big_query_cloud_stats"
playground topic produce -t big_query_cloud_stats --nb-messages 1 --forced-value '{"users": {"name":"Bob","friends": "1000"}}' --key "simple-key-1" << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "users",
      "type": {
        "name": "columnfamily",
        "type": "record",
        "fields": [
          {
            "name": "name",
            "type": "string"
          },
          {
            "name": "friends",
            "type": "string"
          }
        ]
      }
    }
  ]
}
EOF
playground topic produce -t big_query_cloud_stats --nb-messages 1 --forced-value '{"users": {"name":"Jess","friends": "10000"}}' --key "simple-key-2" << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name":"name","type":"string"},{"name":"friends","type":"string"}]}}]}
EOF
playground topic produce -t big_query_cloud_stats --nb-messages 1 --forced-value '{"users": {"name":"John","friends": "10000"}}' --key "simple-key-3" << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name":"name","type":"string"},{"name":"friends","type":"string"}]}}]}
EOF


connector_name="BigTableSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "BigTableSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "big_query_cloud_stats",
  "gcp.bigtable.credentials.json" : "$GCP_KEYFILE_CONTENT",
  "gcp.bigtable.instance.id": "$GCP_BIGTABLE_INSTANCE",
  "gcp.bigtable.project.id": "$GCP_PROJECT",
  "input.data.format" : "AVRO",
  "input.key.format": "STRING",
  "auto.create.tables": "true",
  "auto.create.column.families": "true",
  "table.name.format" : "kafka_\${topic}",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground connector show-lag --connector $connector_name --max-wait 360

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  # not running with github actions
  log "Doing gsutil authentication"
  set +e
  docker rm -f gcloud-config
  set -e
  docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

  log "Verify data is in GCP BigTable"
  docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $GCP_PROJECT -instance $GCP_BIGTABLE_INSTANCE read kafka_big_query_cloud_stats > /tmp/result.log  2>&1
  cat /tmp/result.log
  grep "Bob" /tmp/result.log
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name