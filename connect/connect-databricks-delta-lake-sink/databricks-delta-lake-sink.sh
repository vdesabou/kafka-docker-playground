#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "0.0.99"
then
     logwarn "minimal supported connector version is 1.0.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

cd ../../connect/connect-databricks-delta-lake-sink
if [ ! -f ${DIR}/SparkJDBC42.jar ]
then
     log "Getting SparkJDBC42.jar"
     wget -q https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/jdbc/2.6.22/SimbaSparkJDBC42-2.6.22.1040.zip
     unzip SimbaSparkJDBC42-2.6.22.1040.zip
     rm -rf docs EULA.txt
     rm -f SimbaSparkJDBC42-2.6.22.1040.zip
fi
cd -

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


cd ../../connect/connect-databricks-delta-lake-sink

# Copy JAR files to confluent-hub
mkdir -p ../../confluent-hub/confluentinc-kafka-connect-databricks-delta-lake/lib/
cp ../../connect/connect-databricks-delta-lake-sink/SparkJDBC42.jar ../../confluent-hub/confluentinc-kafka-connect-databricks-delta-lake/lib/SparkJDBC42.jar
cd -
databricks_ensure_sql_warehouse_running "$DATABRICKS_SERVER_HOSTNAME" "$DATABRICKS_TOKEN" "$DATABRICKS_HTTP_PATH"

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Empty bucket <$DATABRICKS_AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$DATABRICKS_AWS_BUCKET_NAME --recursive --region $DATABRICKS_AWS_BUCKET_REGION
set -e

# one table per user: the workspace is shared, and a table created by someone else
# makes COPY INTO fail with [INSUFFICIENT_PERMISSIONS] ... does not have SELECT on Table
# one topic per run: the connector skips (and never auto-creates the table for) records whose offset
# is not above a file left under topics/<topic>/ in the shared staging bucket by an earlier run
# the environment is in the name: CI runs this example in the plaintext and cfk jobs of the same run, at the same time
DATABRICKS_SUFFIX="$(echo "${USER:-playground}_${GITHUB_RUN_NUMBER:-$(date +%s)}_${TAG_BASE}_${PLAYGROUND_ENVIRONMENT}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '_')"
DATABRICKS_TOPIC="pageviews_${DATABRICKS_SUFFIX}"
DATABRICKS_TABLE_NAME="pageviews_${DATABRICKS_SUFFIX}"

log "Sending messages to topic ${DATABRICKS_TOPIC}"
playground topic produce --topic "${DATABRICKS_TOPIC}" --value predefined-schemas/datagen/pageviews_schema.avro --derive-value-schema-as AVRO --nb-messages 100

log "Creating Databricks Delta Lake Sink connector, writing to table ${DATABRICKS_TABLE_NAME}"
playground connector create-or-update --connector databricks-delta-lake-sink  << EOF
{
     "connector.class": "io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkConnector",
     "topics": "${DATABRICKS_TOPIC}",
     "s3.region": "$DATABRICKS_AWS_BUCKET_REGION",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor":1,
     "delta.lake.host.name": "$DATABRICKS_SERVER_HOSTNAME",
     "delta.lake.http.path": "$DATABRICKS_HTTP_PATH",
     "delta.lake.token": "$DATABRICKS_TOKEN",
     "delta.lake.topic2table.map": "${DATABRICKS_TOPIC}:${DATABRICKS_TABLE_NAME}",
     "delta.lake.table.auto.create": "true",
     "staging.s3.access.key.id": "$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID",
     "staging.s3.secret.access.key": "$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY",
     "staging.bucket.name": "$DATABRICKS_AWS_BUCKET_NAME",
     "flush.interval.ms": "100",
     "tasks.max": "1"
}
EOF

sleep 30

playground connector show-lag --max-wait 120

log "Verifying that the 100 records are in table ${DATABRICKS_TABLE_NAME} (the lag reaches 0 even when the COPY INTO fails)"
databricks_wait_for_table_rows "$DATABRICKS_SERVER_HOSTNAME" "$DATABRICKS_TOKEN" "$DATABRICKS_HTTP_PATH" "default.${DATABRICKS_TABLE_NAME}" 100

log "Dropping table ${DATABRICKS_TABLE_NAME} and removing the staged files of topic ${DATABRICKS_TOPIC}, as both are only for this run"
if ! drop_output=$(databricks_sql_statement "$DATABRICKS_SERVER_HOSTNAME" "$DATABRICKS_TOKEN" "$DATABRICKS_HTTP_PATH" "DROP TABLE IF EXISTS default.${DATABRICKS_TABLE_NAME}")
then
     echo "$drop_output"
     logwarn "🧱 could not drop table ${DATABRICKS_TABLE_NAME}"
fi
set +e
(
     export AWS_ACCESS_KEY_ID="$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID"
     export AWS_SECRET_ACCESS_KEY="$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY"
     export AWS_SESSION_TOKEN=""
     aws s3 rm "s3://${DATABRICKS_AWS_BUCKET_NAME}/topics/${DATABRICKS_TOPIC}/" --recursive --region $DATABRICKS_AWS_BUCKET_REGION
)
set -e
