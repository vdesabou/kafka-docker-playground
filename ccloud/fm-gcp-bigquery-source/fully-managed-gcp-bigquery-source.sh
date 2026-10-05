#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$GCP_PROJECT" ]
then
     logerror "GCP_PROJECT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

cd ../../ccloud/fm-gcp-bigquery-source
GCP_KEYFILE="${DIR}/keyfile.json"
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

# the dataset must be in US: with timestamp/incrementing modes, the connector validates the offset columns
# using JDBC DatabaseMetaData.getPrimaryKeys(), which ignores bigquery.query.location and always runs in US
# (Not found: Dataset <project>:<dataset> was not found in location US)
GCP_BIGQUERY_LOCATION=US

bootstrap_ccloud_environment

DATASET=pg${USER}fmsrcds${GITHUB_RUN_NUMBER}${TAG_BASE}
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

log "Create dataset $GCP_PROJECT.$DATASET in location $GCP_BIGQUERY_LOCATION"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" --location "$GCP_BIGQUERY_LOCATION" mk --dataset --label cflt_managed_by:user --label cflt_managed_id:"$USER" --description "used by playground" "$DATASET"

function cleanup_cloud_resources {
  set +e
  log "Drop GCP BigQuery dataset $DATASET"
  check_if_continue
  docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" rm -r -f -d "$DATASET"
  docker rm -f gcloud-config
}
trap cleanup_cloud_resources EXIT

log "Create table $GCP_PROJECT:$DATASET.customers"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" mk --table --description "customers table" $GCP_PROJECT:$DATASET.customers id:INTEGER,first_name:STRING,last_name:STRING,email:STRING,updated_at:TIMESTAMP

log "Insert 2 rows"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" query --nouse_legacy_sql "INSERT INTO $DATASET.customers(id,first_name,last_name,email,updated_at) VALUES (1,'Sally','Thomas','sally.thomas@acme.com',CURRENT_TIMESTAMP()),(2,'George','Bailey','gbailey@foobar.com',CURRENT_TIMESTAMP());"

connector_name="BigQuerySource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "BigQuerySource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "authentication.method": "Google cloud service account",
  "bigquery.credentials.json": "$GCP_KEYFILE_CONTENT",
  "catalog.pattern": "$GCP_PROJECT",
  "schema.pattern": "$DATASET",
  "bigquery.query.location": "$GCP_BIGQUERY_LOCATION",
  "table.include.list": "$GCP_PROJECT.$DATASET.customers",
  "mode": "timestamp+incrementing",
  "timestamp.columns.mapping": ".*customers:[updated_at]",
  "incrementing.column.mapping": ".*customers:id",
  "topic.prefix": "bigquery_",
  "output.data.format": "AVRO",
  "output.key.format": "STRING",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Insert 1 more row"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$GCP_PROJECT" query --nouse_legacy_sql "INSERT INTO $DATASET.customers(id,first_name,last_name,email,updated_at) VALUES (3,'Edward','Walker','ed@walker.com',CURRENT_TIMESTAMP());"

sleep 10

log "Verifying topic bigquery_customers"
playground topic consume --topic bigquery_customers --min-expected-messages 3 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
