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

for component in producer-repro-89593
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-89593-schemaparseexception-cant-redefine-connectdefault.yml"

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
               "topics": "customer_json_schema",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "s3.part.size": 52428801,
               "flush.size": "3",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.parquet.ParquetFormat",
               "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "schema.compatibility": "NONE"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .


log "✨ Run the json-schema java producer which produces to topic customer_json_schema"
docker exec producer-repro-89593 bash -c "java -jar producer-1.0.0-jar-with-dependencies.jar"

sleep 10

log "Listing objects of in S3"
aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

# [2022-01-25 10:08:22,146] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
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
# Caused by: org.apache.avro.SchemaParseException: Can't redefine: io.confluent.connect.avro.ConnectDefault
#         at org.apache.avro.Schema$Names.put(Schema.java:1511)
#         at org.apache.avro.Schema$NamedSchema.writeNameRef(Schema.java:782)
#         at org.apache.avro.Schema$RecordSchema.toJson(Schema.java:943)
#         at org.apache.avro.Schema$ArraySchema.toJson(Schema.java:1102)
#         at org.apache.avro.Schema$UnionSchema.toJson(Schema.java:1203)
#         at org.apache.avro.Schema$RecordSchema.fieldsToJson(Schema.java:971)
#         at org.apache.avro.Schema$RecordSchema.toJson(Schema.java:955)
#         at org.apache.avro.Schema.toString(Schema.java:396)
#         at org.apache.avro.Schema.toString(Schema.java:382)
#         at org.apache.parquet.avro.AvroWriteSupport.init(AvroWriteSupport.java:137)
#         at org.apache.parquet.hadoop.ParquetWriter.<init>(ParquetWriter.java:277)
#         at org.apache.parquet.hadoop.ParquetWriter$Builder.build(ParquetWriter.java:564)
#         at io.confluent.connect.s3.format.parquet.ParquetRecordWriterProvider$1.write(ParquetRecordWriterProvider.java:85)
#         at io.confluent.connect.s3.format.KeyValueHeaderRecordWriterProvider$1.write(KeyValueHeaderRecordWriterProvider.java:104)
#         at io.confluent.connect.s3.TopicPartitionWriter.writeRecord(TopicPartitionWriter.java:555)
#         at io.confluent.connect.s3.TopicPartitionWriter.checkRotationOrAppend(TopicPartitionWriter.java:304)
#         at io.confluent.connect.s3.TopicPartitionWriter.executeState(TopicPartitionWriter.java:247)
#         at io.confluent.connect.s3.TopicPartitionWriter.write(TopicPartitionWriter.java:198)
#         at io.confluent.connect.s3.S3SinkTask.put(S3SinkTask.java:234)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more