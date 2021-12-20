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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.backup-and-restore-proxy.yml"

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
               "topics": "s3_topic",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "s3.part.size": 5242880,
               "flush.size": "3",
               "s3.proxy.url": "https://nginx-proxy:8888",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.compatibility": "NONE"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .


log "Sending messages to topic s3_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing objects of in S3"
aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp --only-show-errors s3://$AWS_BUCKET_NAME/topics/s3_topic/partition=0/s3_topic+0+0000000000.avro s3_topic+0+0000000000.avro

docker run --rm -v ${DIR}:/tmp actions/avro-tools tojson /tmp/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro

log "Creating S3 Source connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "s3.proxy.url": "https://nginx-proxy:8888",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "transforms": "AddPrefix",
               "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.regex": ".*",
               "transforms.AddPrefix.replacement": "copy_of_$0"
          }' \
     http://localhost:8083/connectors/s3-source/config | jq .


log "Verifying topic copy_of_s3_topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic copy_of_s3_topic --from-beginning --max-messages 9


# FIXTHIS: https://confluentinc.atlassian.net/browse/CCMSG-1361
# [2021-09-16 13:37:22,275] ERROR [s3-source|worker] WorkerConnector{id=s3-source} Error while starting connector (org.apache.kafka.connect.runtime.WorkerConnector:193)
# java.lang.IllegalArgumentException: No enum constant com.amazonaws.Protocol.https
#         at java.base/java.lang.Enum.valueOf(Enum.java:240)
#         at com.amazonaws.Protocol.valueOf(Protocol.java:25)
#         at io.confluent.connect.s3.source.util.S3ProxyConfig.<init>(S3ProxyConfig.java:44)
#         at io.confluent.connect.s3.source.S3Storage.newClientConfiguration(S3Storage.java:365)
#         at io.confluent.connect.s3.source.S3Storage.newS3Client(S3Storage.java:407)
#         at io.confluent.connect.s3.source.S3Storage.<init>(S3Storage.java:63)
#         at io.confluent.connect.s3.source.S3SourceConnector.createStorage(S3SourceConnector.java:39)
#         at io.confluent.connect.cloud.storage.source.StorageSourceConnector.start(StorageSourceConnector.java:65)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doStart(WorkerConnector.java:185)
#         at org.apache.kafka.connect.runtime.WorkerConnector.start(WorkerConnector.java:210)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:349)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doTransitionTo(WorkerConnector.java:332)
#         at org.apache.kafka.connect.runtime.WorkerConnector.doRun(WorkerConnector.java:141)
#         at org.apache.kafka.connect.runtime.WorkerConnector.run(WorkerConnector.java:118)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
