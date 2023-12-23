#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


cd ../../connect/connect-databricks-delta-lake-sink
if [ ! -f ${DIR}/SparkJDBC42.jar ]
then
     log "Getting SparkJDBC42.jar"
     wget https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/jdbc/2.6.22/SimbaSparkJDBC42-2.6.22.1040.zip
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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Empty bucket <$DATABRICKS_AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$DATABRICKS_AWS_BUCKET_NAME --recursive --region $DATABRICKS_AWS_BUCKET_REGION
set -e

log "Create topic pageviews"
curl -s -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
               "kafka.topic": "pageviews",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.schemas.enable": "false",
               "max.interval": 10,
               "iterations": "10",
               "tasks.max": "1",
               "quickstart": "pageviews"
          }' \
     http://localhost:8083/connectors/datagen-pageviews/config | jq .

wait_for_datagen_connector_to_inject_data "pageviews" "1"

log "Creating Databricks Delta Lake Sink connector"
playground connector create-or-update --connector databricks-delta-lake-sink --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
     "connector.class": "io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkConnector",
     "topics": "pageviews",
     "s3.region": "$DATABRICKS_AWS_BUCKET_REGION",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor":1,
     "delta.lake.host.name": "$DATABRICKS_SERVER_HOSTNAME",
     "delta.lake.http.path": "$DATABRICKS_HTTP_PATH",
     "delta.lake.token": "$DATABRICKS_TOKEN",
     "delta.lake.topic2table.map": "pageviews:pageviews",
     "delta.lake.table.auto.create": "true",
     "staging.s3.access.key.id": "$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID",
     "staging.s3.secret.access.key": "$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY",
     "staging.bucket.name": "$DATABRICKS_AWS_BUCKET_NAME",
     "flush.interval.ms": "100",
     "tasks.max": "1"
}
EOF


sleep 90

log "Listing staging Amazon S3 bucket"
export AWS_ACCESS_KEY_ID="$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY"
aws s3api list-objects --bucket "$DATABRICKS_AWS_BUCKET_NAME" > /tmp/result.log 2>&1
if [ $? != 0 ]
then
     logerror "FAILED"
     docker container logs connect >  connect.log 2>&1
     tail -500 connect.log
     exit 1
fi

if [ `wc -l /tmp/result.log | cut -d" " -f1` = 0 ]
then
     logerror "FAILED"
     docker container logs connect >  connect.log 2>&1
     tail -500 connect.log
     exit 1
fi

cat /tmp/result.log
