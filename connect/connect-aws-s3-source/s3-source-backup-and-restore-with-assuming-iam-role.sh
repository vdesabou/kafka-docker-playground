#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

export AWS_CREDENTIALS_FILE_NAME=credentials-with-assuming-iam-role
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [ -z "$AWS_REGION" ]
then
     AWS_REGION=$(aws configure get region | tr '\r' '\n')
     if [ "$AWS_REGION" == "" ]
     then
          logerror "ERROR: either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
          exit 1
     fi
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.backup-and-restore.with-assuming-iam-role.yml"

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
playground connector create-or-update --connector s3-sink --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
     "connector.class": "io.confluent.connect.s3.S3SinkConnector",
     "tasks.max": "1",
     "topics": "s3_topic",
     "s3.region": "$AWS_REGION",
     "s3.bucket.name": "$AWS_BUCKET_NAME",
     "topics.dir": "$TAG",
     "s3.part.size": 5242880,
     "flush.size": "3",
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

docker run --rm -v ${DIR}:/tmp vdesabou/avro-tools tojson /tmp/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro

log "Creating Backup and Restore S3 Source connector with bucket name <$AWS_BUCKET_NAME>"
playground connector create-or-update --connector s3-source --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
{
     "tasks.max": "1",
     "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
     "s3.region": "$AWS_REGION",
     "s3.bucket.name": "$AWS_BUCKET_NAME",
     "topics.dir": "$TAG",
     "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
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
