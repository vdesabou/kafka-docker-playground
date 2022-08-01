#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# KNOWN ISSUE
logerror "💀 KNOWN ISSUE: DD-14617"
exit 1



AWS_STS_ROLE_ARN=${AWS_STS_ROLE_ARN:-$1}

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
# this is only used for AWS CLI
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [ -z "$AWS_STS_ROLE_ARN" ]
then
     logerror "AWS_STS_ROLE_ARN is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID" ]
then
     logerror "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY" ]
then
     logerror "AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi


if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

# credentials file is not mounted in connect container
${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.with-assuming-iam-role-config.yml"

AWS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}


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
               "s3.part.size": 52428801,
               "flush.size": "3",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "s3.credentials.provider.class": "io.confluent.connect.s3.auth.AwsAssumeRoleCredentialsProvider",
               "s3.credentials.provider.sts.role.arn": "'"$AWS_STS_ROLE_ARN"'",
               "s3.credentials.provider.sts.role.session.name": "session-name",
               "s3.credentials.provider.sts.role.external.id": "123",
               "aws.access.key.id": "'"$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID"'",
               "aws.secret.access.key": "'"$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY"'",
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