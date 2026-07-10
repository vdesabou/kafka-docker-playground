#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

GCP_SPANNER_INSTANCE="pg${USER}fmsi${GITHUB_RUN_NUMBER}${TAG_BASE}"
GCP_SPANNER_INSTANCE=${GCP_SPANNER_INSTANCE//[-.]/}
GCP_SPANNER_DATABASE="pg${USER}fmsd${GITHUB_RUN_NUMBER}${TAG_BASE}"
GCP_SPANNER_DATABASE=${GCP_SPANNER_DATABASE//[-.]/}
GCP_SPANNER_REGION=${1:-europe-west2}
GCP_SPANNER_CHANGE_STREAM="AllChangesStream"

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
playground topic delete --topic "lcc-.*Items"
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

log "Creating Spanner change stream $GCP_SPANNER_CHANGE_STREAM (required by Spanner CDC Source connector)"
log "See https://docs.confluent.io/cloud/current/connectors/cc-google-spanner-cdc-source-debezium.html#limitations"
log "See https://docs.cloud.google.com/spanner/docs/change-streams/manage#create"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest \
  gcloud spanner databases ddl update $GCP_SPANNER_DATABASE \
  --instance $GCP_SPANNER_INSTANCE \
  --project $GCP_PROJECT \
  --ddl="CREATE CHANGE STREAM $GCP_SPANNER_CHANGE_STREAM FOR ALL"

log "Creating table Items so we can generate change-stream events"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest \
  gcloud spanner databases ddl update $GCP_SPANNER_DATABASE \
  --instance $GCP_SPANNER_INSTANCE \
  --project $GCP_PROJECT \
  --ddl="CREATE TABLE Items (ItemId INT64 NOT NULL, Name STRING(1024), Price INT64, LastUpdated TIMESTAMP OPTIONS (allow_commit_timestamp=true)) PRIMARY KEY (ItemId)"

function cleanup_cloud_resources {

  log "Deleting GCP Spanner database $GCP_SPANNER_DATABASE"
  check_if_continue
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

connector_name="SpannerCdcSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "SpannerCdcSource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "gcp.spanner.credentials.json" : "$GCP_KEYFILE_CONTENT",
  "gcp.spanner.project.id" : "$GCP_PROJECT",
  "gcp.spanner.instance.id" : "$GCP_SPANNER_INSTANCE",
  "gcp.spanner.database.id" : "$GCP_SPANNER_DATABASE",
  "gcp.spanner.change.stream" : "$GCP_SPANNER_CHANGE_STREAM",
  "output.data.format": "AVRO",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Inserting and mutating Spanner data to produce change-stream records"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest \
  gcloud spanner databases execute-sql $GCP_SPANNER_DATABASE \
  --instance=$GCP_SPANNER_INSTANCE \
  --project=$GCP_PROJECT \
  --sql="INSERT INTO Items (ItemId, Name, Price, LastUpdated) VALUES (1, 'apple', 10, PENDING_COMMIT_TIMESTAMP())"

docker run -i --volumes-from gcloud-config google/cloud-sdk:latest \
  gcloud spanner databases execute-sql $GCP_SPANNER_DATABASE \
  --instance=$GCP_SPANNER_INSTANCE \
  --project=$GCP_PROJECT \
  --sql="INSERT INTO Items (ItemId, Name, Price, LastUpdated) VALUES (2, 'banana', 20, PENDING_COMMIT_TIMESTAMP())"

docker run -i --volumes-from gcloud-config google/cloud-sdk:latest \
  gcloud spanner databases execute-sql $GCP_SPANNER_DATABASE \
  --instance=$GCP_SPANNER_INSTANCE \
  --project=$GCP_PROJECT \
  --sql="UPDATE Items SET Price = 30, LastUpdated = PENDING_COMMIT_TIMESTAMP() WHERE ItemId = 2"

docker run -i --volumes-from gcloud-config google/cloud-sdk:latest \
  gcloud spanner databases execute-sql $GCP_SPANNER_DATABASE \
  --instance=$GCP_SPANNER_INSTANCE \
  --project=$GCP_PROJECT \
  --sql="DELETE FROM Items WHERE ItemId = 1"

log "✅ Generated INSERT/UPDATE/DELETE events for change stream $GCP_SPANNER_CHANGE_STREAM"


sleep 10

connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic $connectorId.Items"
playground topic consume --topic $connectorId.Items --min-expected-messages 3 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name