#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$CI" ]
then
     # running with github actions
     if [ ! -f ../../secrets.properties ]
     then
          logerror "../../secrets.properties is not present!"
          exit 1
     fi
     source ../../secrets.properties > /dev/null 2>&1
fi

if [ ! -f ${DIR}/SparkJDBC42.jar ]
then
     log "Getting SparkJDBC42.jar"
     wget https://databricks-bi-artifacts.s3.us-east-2.amazonaws.com/simbaspark-drivers/jdbc/2.6.22/SimbaSparkJDBC42-2.6.22.1040.zip
     unzip SimbaSparkJDBC42-2.6.22.1040.zip
     rm -rf docs EULA.txt
     rm -f SimbaSparkJDBC42-2.6.22.1040.zip
fi

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-106170-seems-to-only-work-with-a-single-topic.yml"

log "Empty bucket <$DATABRICKS_AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$DATABRICKS_AWS_BUCKET_NAME --recursive --region $DATABRICKS_AWS_BUCKET_REGION
set -e

for((i=0;i<30;i++)); do
     TOPIC="pageviews$i"
     log "Create topic $TOPIC"

     curl -s -X PUT \
          -H "Content-Type: application/json" \
          --data '{
                    "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
                    "kafka.topic": "'"$TOPIC"'",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "io.confluent.connect.avro.AvroConverter",
                    "value.converter.schema.registry.url": "http://schema-registry:8081",
                    "value.converter.schemas.enable": "false",
                    "max.interval": 1,
                    "iterations": "10",
                    "tasks.max": "1",
                    "quickstart": "pageviews"
               }' \
          http://localhost:8083/connectors/datagen-$TOPIC/config | jq .

     wait_for_datagen_connector_to_inject_data "$TOPIC" "1"
     curl -X DELETE localhost:8083/connectors/datagen-$TOPIC
done



log "Creating Databricks Delta Lake Sink connector with 15 topics"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkConnector",
               "topics": "pageviews0,pageviews1,pageviews2,pageviews3,pageviews4,pageviews5,pageviews6,pageviews7,pageviews8,pageviews9,pageviews10,pageviews11,pageviews12,pageviews13,pageviews14",
               "s3.region": "'"$DATABRICKS_AWS_BUCKET_REGION"'",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor":1,
               "delta.lake.host.name": "'"$DATABRICKS_SERVER_HOSTNAME"'",
               "delta.lake.http.path": "'"$DATABRICKS_HTTP_PATH"'",
               "delta.lake.token": "'"$DATABRICKS_TOKEN"'",
               "delta.lake.topic2table.map": "pageviews0:pageviews0,pageviews1:pageviews1,pageviews2:pageviews2,pageviews3:pageviews3,pageviews4:pageviews4,pageviews5:pageviews5,pageviews6:pageviews6,pageviews7:pageviews7,pageviews8:pageviews8,pageviews9:pageviews9,pageviews10:pageviews10,pageviews11:pageviews11,pageviews12:pageviews12,pageviews13:pageviews13,pageviews14:pageviews14",
               "delta.lake.table.auto.create": "true",
               "staging.s3.access.key.id": "'"$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID"'",
               "staging.s3.secret.access.key": "'"$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY"'",
               "staging.bucket.name": "'"$DATABRICKS_AWS_BUCKET_NAME"'",
               "flush.interval.ms": "10000",
               "tasks.max": "1"

          }' \
     http://localhost:8083/connectors/databricks-delta-lake-sink/config | jq .


sleep 10


log "Listing staging Amazon S3 bucket"
export AWS_ACCESS_KEY_ID="$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY"
aws s3api list-objects --bucket "$DATABRICKS_AWS_BUCKET_NAME"

exit 0
log "sleep 3 minutes"
sleep 180

log "restart task"
curl -X POST localhost:8083/connectors/databricks-delta-lake-sink/tasks/0/restart

# [2022-05-24 13:26:19,475] ERROR [databricks-delta-lake-sink|task-0] WorkerSinkTask{id=databricks-delta-lake-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: null (org.apache.kafka.connect.runtime.WorkerSinkTask:616)
# java.lang.NullPointerException
#         at io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkTask.getS3Files(DatabricksDeltaLakeSinkTask.java:208)
#         at io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkTask.put(DatabricksDeltaLakeSinkTask.java:94)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-05-24 13:26:19,476] ERROR [databricks-delta-lake-sink|task-0] WorkerSinkTask{id=databricks-delta-lake-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:207)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:618)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:200)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:255)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.lang.NullPointerException
#         at io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkTask.getS3Files(DatabricksDeltaLakeSinkTask.java:208)
#         at io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkTask.put(DatabricksDeltaLakeSinkTask.java:94)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:584)
#         ... 10 more

exit 0

log "Updating Databricks Delta Lake Sink connector with 30 topics"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.databricks.deltalake.DatabricksDeltaLakeSinkConnector",
               "topics": "pageviews0,pageviews1,pageviews2,pageviews3,pageviews4,pageviews5,pageviews6,pageviews7,pageviews8,pageviews9,pageviews10,pageviews11,pageviews12,pageviews13,pageviews14,pageviews15,pageviews16,pageviews17,pageviews18,pageviews19,pageviews20,pageviews21,pageviews22,pageviews23,pageviews24,pageviews25,pageviews26,pageviews27,pageviews28,pageviews29",
               "s3.region": "'"$DATABRICKS_AWS_BUCKET_REGION"'",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor":1,
               "delta.lake.host.name": "'"$DATABRICKS_SERVER_HOSTNAME"'",
               "delta.lake.http.path": "'"$DATABRICKS_HTTP_PATH"'",
               "delta.lake.token": "'"$DATABRICKS_TOKEN"'",
               "delta.lake.topic2table.map": "pageviews0:pageviews0,pageviews1:pageviews1,pageviews2:pageviews2,pageviews3:pageviews3,pageviews4:pageviews4,pageviews5:pageviews5,pageviews6:pageviews6,pageviews7:pageviews7,pageviews8:pageviews8,pageviews9:pageviews9,pageviews10:pageviews10,pageviews11:pageviews11,pageviews12:pageviews12,pageviews13:pageviews13,pageviews14:pageviews14,pageviews15:pageviews15,pageviews16:pageviews16,pageviews17:pageviews17,pageviews18:pageviews18,pageviews19:pageviews19,pageviews20:pageviews20,pageviews21:pageviews21,pageviews22:pageviews22,pageviews23:pageviews23,pageviews24:pageviews24,pageviews25:pageviews25,pageviews26:pageviews26,pageviews27:pageviews27,pageviews28:pageviews28,pageviews29:pageviews29",
               "delta.lake.table.auto.create": "true",
               "staging.s3.access.key.id": "'"$DATABRICKS_AWS_STAGING_S3_ACCESS_KEY_ID"'",
               "staging.s3.secret.access.key": "'"$DATABRICKS_AWS_STAGING_S3_SECRET_ACCESS_KEY"'",
               "staging.bucket.name": "'"$DATABRICKS_AWS_BUCKET_NAME"'",
               "flush.interval.ms": "100",
               "tasks.max": "1"

          }' \
     http://localhost:8083/connectors/databricks-delta-lake-sink/config | jq .


