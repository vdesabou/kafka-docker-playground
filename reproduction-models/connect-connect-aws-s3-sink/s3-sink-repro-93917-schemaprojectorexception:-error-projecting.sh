#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

for component in producer-repro-93917 producer-repro-93917-2
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-93917-schemaprojectorexception:-error-projecting.yml"

AWS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}

AWS_REGION=$(aws configure get region | tr '\r' '\n')
log "Creating bucket name <$AWS_BUCKET_NAME>, if required"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME --recursive --region $AWS_REGION
set -e

log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "customer_avro",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "s3.part.size": 52428801,
               "flush.size": "5000",
               "key.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
               "schema.compatibility": "BACKWARD",
               "behavior.on.null.values": "ignore",
               "connect.meta.data": "false",
               "enhanced.avro.schema.support": "true",
               "rotate.interval.ms": "180000",
               "schemas.cache.config": "1000",
               "s3.compression.type": "gzip",
               "s3.compression.level": "9",
               "s3.part.retries" : "10000",
               "s3.part.size": "5242880",

               "locale": "en",
               "partition.duration.ms": "3600000",
               "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
               "path.format": "YYYY/MM/dd/HH",
               "timestamp.extractor": "Record",
               "timestamp.field": "timestamp",
               "timezone": "UTC",

               "errors.tolerance": "all",
               "errors.deadletterqueue.topic.name": "dlq",
               "errors.deadletterqueue.topic.replication.factor": "1",
               "errors.deadletterqueue.context.headers.enable": "true",
               "errors.log.enable": "true",
               "errors.log.include.messages": "false",
               "errors.retry.delay.max.ms": "60000",
               "errors.retry.timeout": "0"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .



log "Register first version using producer-repro-93917/src/main/resources/avro/customer.avsc"
escaped_json=$(jq -c -Rs '.' producer-repro-93917/src/main/resources/avro/customer.avsc)
cat << EOF > /tmp/final.json
{"schema":$escaped_json}
EOF

log "Register new version v1 for schema customer_avro-value"
curl -X POST http://localhost:8081/subjects/customer_avro-value/versions \
--header 'Content-Type: application/vnd.schemaregistry.v1+json' \
--data @/tmp/final.json

log "✨ Run a java producer which produces to topic customer_avro, it runs 1 message per second"
docker exec -d producer-repro-93917 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Register second version using producer-repro-93917-2/src/main/resources/avro/customer.avsc"
escaped_json=$(jq -c -Rs '.' producer-repro-93917-2/src/main/resources/avro/customer.avsc)

cat << EOF > /tmp/final.json
{"schema":$escaped_json}
EOF

log "Register new version v2 for schema customer_avro-value"
curl -X POST http://localhost:8081/subjects/customer_avro-value/versions \
--header 'Content-Type: application/vnd.schemaregistry.v1+json' \
--data @/tmp/final.json

log "✨ Run a java producer which produces to topic customer_avro, it runs 1 message per second"
docker exec -d producer-repro-93917-2 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"


# [2022-03-07 14:13:34,799] WARN [s3-sink|task-0] Errant record written to DLQ due to: Error projecting client_background_music_option (io.confluent.connect.s3.TopicPartitionWriter:204)
# [2022-03-07 14:13:34,799] ERROR [s3-sink|task-0] Error encountered in task s3-sink-0. Executing stage 'TASK_PUT' with class 'org.apache.kafka.connect.sink.SinkTask'. (org.apache.kafka.connect.runtime.errors.LogReporter:66)
# org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting client_background_music_option
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:113)
#         at org.apache.kafka.connect.data.SchemaProjector.projectRequiredSchema(SchemaProjector.java:93)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:73)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:395)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:383)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.project(StorageSchemaCompatibility.java:355)
#         at io.confluent.connect.s3.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:303)
#         at io.confluent.connect.s3.TopicPartitionWriter.executeState(TopicPartitionWriter.java:247)
#         at io.confluent.connect.s3.TopicPartitionWriter.write(TopicPartitionWriter.java:198)
#         at io.confluent.connect.s3.S3SinkTask.put(S3SinkTask.java:234)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {io.confluent.connect.avro.record.doc=this is a doc, io.confluent.connect.avro.field.doc.action=this is a doc, io.confluent.connect.avro.field.doc.adid=this is a doc, io.confluent.connect.avro.field.doc.client_number_version=this is a doc, io.confluent.connect.avro.field.doc.idfa_or_gps_adid=this is a doc, io.confluent.connect.avro.field.doc.network=this is a doc, io.confluent.connect.avro.field.doc.campaign=this is a doc, io.confluent.connect.avro.field.doc.adgroup=this is a doc, io.confluent.connect.avro.field.doc.creative=this is a doc, io.confluent.connect.avro.field.doc.sn_type=this is a doc, io.confluent.connect.avro.field.doc.user_sn_id=this is a doc, io.confluent.connect.avro.field.doc.session_id=this is a doc, io.confluent.connect.avro.field.doc.exp=this is a doc, io.confluent.connect.avro.field.doc.rp=this is a doc, io.confluent.connect.avro.field.doc.coin=this is a doc, io.confluent.connect.avro.field.doc.day=this is a doc, io.confluent.connect.avro.field.doc.device_id=this is a doc, io.confluent.connect.avro.field.doc.event_id=this is a doc, io.confluent.connect.avro.field.doc.id=this is a doc, io.confluent.connect.avro.field.doc.level=this is a doc, io.confluent.connect.avro.field.doc.login_ct=this is a doc, io.confluent.connect.avro.field.doc.ltv=this is a doc, io.confluent.connect.avro.field.doc.os=this is a doc, io.confluent.connect.avro.field.doc.purchase_ct=this is a doc, io.confluent.connect.avro.field.doc.reg_ts=this is a doc, io.confluent.connect.avro.field.doc.spt=this is a doc, io.confluent.connect.avro.field.doc.tier=this is a doc, io.confluent.connect.avro.field.doc.total_spt=this is a doc, io.confluent.connect.avro.field.doc.ts=this is a doc, io.confluent.connect.avro.field.doc.user_id=this is a doc, io.confluent.connect.avro.field.doc.merge_source=this is a doc, io.confluent.connect.avro.field.doc.merge_destination=this is a doc, io.confluent.connect.avro.field.doc.merge_ts=this is a doc, io.confluent.connect.avro.field.doc.user_club_id=this is a doc, io.confluent.connect.avro.field.doc.user_club_authority=this is a doc, io.confluent.connect.avro.field.doc.gem=this is a doc, io.confluent.connect.avro.field.doc.free_gem=this is a doc} and target parameters: {io.confluent.connect.avro.record.doc=this is a doc, io.confluent.connect.avro.field.doc.action=this is a doc, io.confluent.connect.avro.field.doc.adid=this is a doc, io.confluent.connect.avro.field.doc.client_number_version=this is a doc, io.confluent.connect.avro.field.doc.idfa_or_gps_adid=this is a doc, io.confluent.connect.avro.field.doc.network=this is a doc, io.confluent.connect.avro.field.doc.campaign=this is a doc, io.confluent.connect.avro.field.doc.adgroup=this is a doc, io.confluent.connect.avro.field.doc.creative=this is a doc, io.confluent.connect.avro.field.doc.sn_type=this is a doc, io.confluent.connect.avro.field.doc.user_sn_id=this is a doc, io.confluent.connect.avro.field.doc.session_id=this is a doc, io.confluent.connect.avro.field.doc.exp=this is a doc, io.confluent.connect.avro.field.doc.rp=this is a doc, io.confluent.connect.avro.field.doc.coin=this is a doc, io.confluent.connect.avro.field.doc.day=this is a doc, io.confluent.connect.avro.field.doc.device_id=this is a doc, io.confluent.connect.avro.field.doc.event_id=this is a doc, io.confluent.connect.avro.field.doc.id=this is a doc, io.confluent.connect.avro.field.doc.level=this is a doc, io.confluent.connect.avro.field.doc.login_ct=this is a doc, io.confluent.connect.avro.field.doc.ltv=this is a doc, io.confluent.connect.avro.field.doc.os=this is a doc, io.confluent.connect.avro.field.doc.purchase_ct=this is a doc, io.confluent.connect.avro.field.doc.reg_ts=this is a doc, io.confluent.connect.avro.field.doc.spt=this is a doc, io.confluent.connect.avro.field.doc.tier=this is a doc, io.confluent.connect.avro.field.doc.total_spt=this is a doc, io.confluent.connect.avro.field.doc.ts=this is a doc, io.confluent.connect.avro.field.doc.user_id=this is a doc, io.confluent.connect.avro.field.doc.merge_source=this is a doc, io.confluent.connect.avro.field.doc.merge_destination=this is a doc, io.confluent.connect.avro.field.doc.merge_ts=this is a doc, io.confluent.connect.avro.field.doc.user_club_id=this is a doc, io.confluent.connect.avro.field.doc.user_club_authority=this is a doc, io.confluent.connect.avro.field.doc.gem=this is a doc, io.confluent.connect.avro.field.doc.free_gem=this is a doc, io.confluent.connect.avro.field.doc.tracker_name=my added field}
#         at org.apache.kafka.connect.data.SchemaProjector.checkMaybeCompatible(SchemaProjector.java:133)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:60)
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:110)
#         ... 20 more