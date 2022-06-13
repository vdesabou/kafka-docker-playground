#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $CONNECTOR_TAG "1.9.9"; then
    # skipped
    logwarn "WARN: skipped as it requires connector version 2.0.0"
    exit 111
fi

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.generalized.repro-109361-read-file-line-by-line-instead-of-the-whole-file.yml"

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


log "Copy repro-109361.mime to bucket $AWS_BUCKET_NAME/quickstart"
aws s3 cp repro-109361.mime s3://$AWS_BUCKET_NAME/quickstart/repro-109361.mime

log "Creating Generalized S3 Source connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "format.class": "io.confluent.connect.s3.format.bytearray.ByteArrayFormat",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "format.bytearray.separator": "xyxyxyxyxyyxyxyxyyxyxyxyxyyxyxyyxyxyyxy",
               "confluent.license": "",
               "mode": "GENERIC",
               "topics.dir": "quickstart",
               "topic.regex.list": "quick-start-topic:.*",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/s3-source-generalized2/config | jq .


log "Verifying topic quick-start-topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic quick-start-topic --from-beginning --max-messages 1
# From: Some One <someone@example.com>
# MIME-Version: 1.0
# Content-Type: multipart/mixed;
#         boundary="XXXXboundary text"

# This is a multipart message in MIME format.

# --XXXXboundary text
# Content-Type: text/plain

# this is the body text

# --XXXXboundary text
# Content-Type: text/plain;
# Content-Disposition: attachment;
#         filename="test.txt"

# this is the attachment text

# --XXXXboundary text--
# Processed a total of 1 messages