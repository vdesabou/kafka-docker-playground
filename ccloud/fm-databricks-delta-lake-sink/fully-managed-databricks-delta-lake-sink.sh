#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

DATABRICKS_AWS_BUCKET_NAME=${DATABRICKS_AWS_BUCKET_NAME:-$1}
DATABRICKS_AWS_BUCKET_REGION=${DATABRICKS_AWS_BUCKET_REGION:-$2}
DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID=${DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID:-$3}
DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY=${DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY:-$4}

DATABRICKS_SERVER_HOSTNAME=${DATABRICKS_SERVER_HOSTNAME:-$5}
DATABRICKS_HTTP_PATH=${DATABRICKS_HTTP_PATH:-$6}
DATABRICKS_TOKEN=${DATABRICKS_TOKEN:-$7}

if [ -z "$DATABRICKS_AWS_BUCKET_NAME" ]
then
     logerror "DATABRICKS_AWS_BUCKET_NAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DATABRICKS_AWS_BUCKET_REGION" ]
then
     logerror "DATABRICKS_AWS_BUCKET_REGION is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID" ]
then
     logerror "DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY" ]
then
     logerror "DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DATABRICKS_SERVER_HOSTNAME" ]
then
     logerror "DATABRICKS_SERVER_HOSTNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DATABRICKS_HTTP_PATH" ]
then
     logerror "DATABRICKS_HTTP_PATH is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DATABRICKS_TOKEN" ]
then
     logerror "DATABRICKS_TOKEN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


databricks_ensure_sql_warehouse_running "$DATABRICKS_SERVER_HOSTNAME" "$DATABRICKS_TOKEN" "$DATABRICKS_HTTP_PATH"

bootstrap_ccloud_environment



log "Empty bucket <$DATABRICKS_AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$DATABRICKS_AWS_BUCKET_NAME --recursive --region $DATABRICKS_AWS_BUCKET_REGION
set -e

set +e
playground topic delete --topic pageviews
sleep 3
playground topic create --topic pageviews --nb-partitions 1
set -e

playground topic produce --topic pageviews --value predefined-schemas/datagen/pageviews_schema.avro --derive-value-schema-as AVRO --nb-messages 100

connector_name="DatabricksDeltaLakeSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

# one table per user: the workspace is shared, and a table created by someone else
# makes COPY INTO fail with [INSUFFICIENT_PERMISSIONS] ... does not have SELECT on Table
DATABRICKS_TABLE_NAME="pageviews_fm_$(echo "${USER:-playground}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '_')"

log "Dropping table ${DATABRICKS_TABLE_NAME} if it exists, so that it holds only the records of this run"
databricks_sql_statement "$DATABRICKS_SERVER_HOSTNAME" "$DATABRICKS_TOKEN" "$DATABRICKS_HTTP_PATH" "DROP TABLE IF EXISTS default.${DATABRICKS_TABLE_NAME}"

log "Creating fully managed connector, writing to table ${DATABRICKS_TABLE_NAME}"
playground connector create-or-update --connector $connector_name << EOF
{
     "topics": "pageviews",
     "input.data.format": "AVRO",
     "name": "$connector_name",
     "connector.class": "DatabricksDeltaLakeSink",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "delta.lake.host.name": "$DATABRICKS_SERVER_HOSTNAME",
     "delta.lake.http.path": "$DATABRICKS_HTTP_PATH",
     "delta.lake.token": "$DATABRICKS_TOKEN",
     "delta.lake.topic2table.map": "pageviews:${DATABRICKS_TABLE_NAME}",
     "delta.lake.table.auto.create": "true",
     "staging.s3.access.key.id": "$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID",
     "staging.s3.secret.access.key": "$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY",
     "staging.bucket.name": "$DATABRICKS_AWS_BUCKET_NAME",
     "flush.interval.ms": "100",
     "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground connector show-lag --connector $connector_name --max-wait 300

log "Verifying that the 100 records are in table ${DATABRICKS_TABLE_NAME} (the lag reaches 0 even when the COPY INTO fails)"
databricks_wait_for_table_rows "$DATABRICKS_SERVER_HOSTNAME" "$DATABRICKS_TOKEN" "$DATABRICKS_HTTP_PATH" "default.${DATABRICKS_TABLE_NAME}" 100

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
