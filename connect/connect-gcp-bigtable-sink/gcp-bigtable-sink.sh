#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.9.99"
then
     logwarn "minimal supported connector version is 2.0.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

GCP_BIGTABLE_REGION=${1:-europe-west2-a}
GCP_BIGTABLE_INSTANCE="pg${USER}bg${GITHUB_RUN_NUMBER}${TAG_BASE}"
GCP_BIGTABLE_INSTANCE=${GCP_BIGTABLE_INSTANCE//[-.]/}

cd ../../connect/connect-gcp-bigtable-sink
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
  log "Delete GCP BigTable table kafka_big_query_stats"
  check_if_continue
  docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $GCP_PROJECT -instance $GCP_BIGTABLE_INSTANCE deletetable kafka_big_query_stats

  log "Delete GCP BigTable instance $GCP_BIGTABLE_INSTANCE"
  check_if_continue
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest gcloud bigtable instances delete $GCP_BIGTABLE_INSTANCE --project $GCP_PROJECT  << EOF
Y
EOF

  docker rm -f gcloud-config
}
trap cleanup_cloud_resources EXIT

log "Sending messages to topic big_query_stats"
playground topic produce -t big_query_stats --nb-messages 1 --forced-value '{"users": {"name":"Bob","friends": "1000"}}' --key "simple-key-1" << 'EOF'
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
playground topic produce -t big_query_stats --nb-messages 1 --forced-value '{"users": {"name":"Jess","friends": "10000"}}' --key "simple-key-2" << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name":"name","type":"string"},{"name":"friends","type":"string"}]}}]}
EOF
playground topic produce -t big_query_stats --nb-messages 1 --forced-value '{"users": {"name":"John","friends": "10000"}}' --key "simple-key-3" << 'EOF'
{"type":"record","name":"myrecord","fields":[{"name":"users","type":{"name":"columnfamily","type":"record","fields":[{"name":"name","type":"string"},{"name":"friends","type":"string"}]}}]}
EOF

log "Creating GCP BigTable Sink connector"
playground connector create-or-update --connector gcp-bigtable-sink  << EOF
{
    "connector.class": "io.confluent.connect.gcp.bigtable.BigtableSinkConnector",
    "tasks.max" : "1",
    "topics" : "big_query_stats",
    "auto.create" : "true",
    "gcp.bigtable.credentials.path": "/tmp/keyfile.json",
    "gcp.bigtable.instance.id": "$GCP_BIGTABLE_INSTANCE",
    "gcp.bigtable.project.id": "$GCP_PROJECT",
    "auto.create.tables": "true",
    "auto.create.column.families": "true",
    "table.name.format" : "kafka_\${topic}",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

playground connector show-lag --connector gcp-bigtable-sink --max-wait 360

if [ -z "$GITHUB_RUN_NUMBER" ]
then
  # not running with github actions
  log "Doing gsutil authentication"
  set +e
  docker rm -f gcloud-config
  set -e
  docker run -i -v ${GCP_KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${GCP_PROJECT} --key-file /tmp/keyfile.json

  log "Verify data is in GCP BigTable"
  docker run -i --volumes-from gcloud-config google/cloud-sdk:latest cbt -project $GCP_PROJECT -instance $GCP_BIGTABLE_INSTANCE read kafka_big_query_stats > /tmp/result.log  2>&1
  cat /tmp/result.log
  grep "Bob" /tmp/result.log
fi