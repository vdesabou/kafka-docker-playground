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

for component in producer-repro-97733 producer-repro-97733-2
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-97733-schemaprojectorexception-error-projecting-source.yml"

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
               "flush.size": "3",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter.connect.meta.data": "false",
               "connect.meta.data": "false",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.compatibility": "FORWARD"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .


log "✨ Run the avro java producer which produces to topic customer_avro"
docker exec producer-repro-97733 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing objects of in S3"
aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "✨ Run the avro java producer which produces to topic customer_avro with additional enum"
docker exec producer-repro-97733-2 bash -c "java ${JAVA_OPTS} -jar producer-1.0.0-jar-with-dependencies.jar"


# [2022-03-28 07:33:12,054] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted. Error: Error projecting channel (org.apache.kafka.connect.runtime.WorkerSinkTask:636)
# org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting channel
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:113)
#         at org.apache.kafka.connect.data.SchemaProjector.projectRequiredSchema(SchemaProjector.java:93)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:73)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:395)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:383)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.project(StorageSchemaCompatibility.java:355)
#         at io.confluent.connect.s3.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:302)
#         at io.confluent.connect.s3.TopicPartitionWriter.executeState(TopicPartitionWriter.java:246)
#         at io.confluent.connect.s3.TopicPartitionWriter.write(TopicPartitionWriter.java:197)
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
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {io.confluent.connect.avro.Enum=com.github.vdesabou.Channel, io.confluent.connect.avro.Enum.UNKNOWN=UNKNOWN, io.confluent.connect.avro.Enum.BOOK=BOOK, io.confluent.connect.avro.Enum.LINE=LINE, io.confluent.connect.avro.Enum.TEST=TEST, io.confluent.connect.avro.Enum.TV=TV, io.confluent.connect.avro.Enum.CABLE=CABLE, io.confluent.connect.avro.Enum.EXTERNAL=EXTERNAL} and target parameters: {io.confluent.connect.avro.Enum=com.github.vdesabou.Channel, io.confluent.connect.avro.Enum.UNKNOWN=UNKNOWN, io.confluent.connect.avro.Enum.BOOK=BOOK, io.confluent.connect.avro.Enum.LINE=LINE, io.confluent.connect.avro.Enum.TEST=TEST, io.confluent.connect.avro.Enum.TV=TV, io.confluent.connect.avro.Enum.CABLE=CABLE}
#         at org.apache.kafka.connect.data.SchemaProjector.checkMaybeCompatible(SchemaProjector.java:133)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:60)
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:110)
#         ... 20 more
# [2022-03-28 07:33:12,060] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
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
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Error projecting channel
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:113)
#         at org.apache.kafka.connect.data.SchemaProjector.projectRequiredSchema(SchemaProjector.java:93)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:73)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:395)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.projectInternal(StorageSchemaCompatibility.java:383)
#         at io.confluent.connect.storage.schema.StorageSchemaCompatibility.project(StorageSchemaCompatibility.java:355)
#         at io.confluent.connect.s3.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:302)
#         at io.confluent.connect.s3.TopicPartitionWriter.executeState(TopicPartitionWriter.java:246)
#         at io.confluent.connect.s3.TopicPartitionWriter.write(TopicPartitionWriter.java:197)
#         at io.confluent.connect.s3.S3SinkTask.put(S3SinkTask.java:234)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: org.apache.kafka.connect.errors.SchemaProjectorException: Schema parameters not equal. source parameters: {io.confluent.connect.avro.Enum=com.github.vdesabou.Channel, io.confluent.connect.avro.Enum.UNKNOWN=UNKNOWN, io.confluent.connect.avro.Enum.BOOK=BOOK, io.confluent.connect.avro.Enum.LINE=LINE, io.confluent.connect.avro.Enum.TEST=TEST, io.confluent.connect.avro.Enum.TV=TV, io.confluent.connect.avro.Enum.CABLE=CABLE, io.confluent.connect.avro.Enum.EXTERNAL=EXTERNAL} and target parameters: {io.confluent.connect.avro.Enum=com.github.vdesabou.Channel, io.confluent.connect.avro.Enum.UNKNOWN=UNKNOWN, io.confluent.connect.avro.Enum.BOOK=BOOK, io.confluent.connect.avro.Enum.LINE=LINE, io.confluent.connect.avro.Enum.TEST=TEST, io.confluent.connect.avro.Enum.TV=TV, io.confluent.connect.avro.Enum.CABLE=CABLE}
#         at org.apache.kafka.connect.data.SchemaProjector.checkMaybeCompatible(SchemaProjector.java:133)
#         at org.apache.kafka.connect.data.SchemaProjector.project(SchemaProjector.java:60)
#         at org.apache.kafka.connect.data.SchemaProjector.projectStruct(SchemaProjector.java:110)
#         ... 20 more
