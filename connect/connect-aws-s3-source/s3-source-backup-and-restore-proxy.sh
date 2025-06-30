#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "2.6.15"
then
     logwarn "minimal supported connector version is 2.6.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.backup-and-restore-proxy.yml"

AWS_BUCKET_NAME=pg-bucket-${USER}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}



log "Empty bucket <$AWS_BUCKET_NAME/$TAG>, if required"
set +e
if [ "$AWS_REGION" == "us-east-1" ]
then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME/$TAG --recursive --region $AWS_REGION
set -e

log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
playground connector create-or-update --connector s3-sink  << EOF
{
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "tasks.max": "1",
    "topics": "s3_topic",
    "s3.region": "$AWS_REGION",
    "s3.bucket.name": "$AWS_BUCKET_NAME",
    "topics.dir": "$TAG",
    "s3.part.size": 5242880,
    "flush.size": "3",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "s3.proxy.url": "https://nginx-proxy:8888",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
    "schema.compatibility": "NONE",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF


log "Sending messages to topic s3_topic"
playground topic produce -t s3_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

sleep 10

# log "Listing objects of in S3"
# aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp --only-show-errors s3://$AWS_BUCKET_NAME/$TAG/s3_topic/partition=0/s3_topic+0+0000000000.avro s3_topic+0+0000000000.avro

playground tools read-avro-file --file $PWD/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro

log "Creating Backup and Restore S3 Source connector with bucket name <$AWS_BUCKET_NAME>"
playground connector create-or-update --connector s3-source  << EOF
{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "$AWS_REGION",
               "s3.bucket.name": "$AWS_BUCKET_NAME",
               "topics.dir": "$TAG",
               "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
               "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "s3.proxy.url": "https://nginx-proxy:8888",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "transforms": "AddPrefix",
               "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.regex": ".*",
               "transforms.AddPrefix.replacement": "copy_of_\$0"
          }
EOF

sleep 10

log "Verifying topic copy_of_s3_topic"
playground topic consume --topic copy_of_s3_topic --min-expected-messages 9 --timeout 60


# FIXTHIS: DDNTH-1361
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
