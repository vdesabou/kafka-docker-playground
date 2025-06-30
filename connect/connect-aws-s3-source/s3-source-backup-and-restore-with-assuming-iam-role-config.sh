#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $CONNECTOR_TAG "2.5.0"; then
    logwarn "WARN: this is available since version 2.5.1 only"
    exit 1
fi

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "2.6.15"
then
     logwarn "minimal supported connector version is 2.6.16 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

AWS_STS_ROLE_ARN=${AWS_STS_ROLE_ARN:-$1}

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

handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.backup-and-restore.with-assuming-iam-role-config.yml"

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
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
    "schema.compatibility": "NONE",
    "s3.credentials.provider.class": "io.confluent.connect.s3.auth.AwsAssumeRoleCredentialsProvider",
    "s3.credentials.provider.sts.role.arn": "$AWS_STS_ROLE_ARN",
    "s3.credentials.provider.sts.role.session.name": "session-name",
    "s3.credentials.provider.sts.role.external.id": "123",
    "aws.access.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY",
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
  "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
  "confluent.license": "",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1",
  "s3.credentials.provider.class": "io.confluent.connect.s3.auth.AwsAssumeRoleCredentialsProvider",
  "s3.credentials.provider.sts.role.arn": "$AWS_STS_ROLE_ARN",
  "s3.credentials.provider.sts.role.session.name": "session-name",
  "s3.credentials.provider.sts.role.external.id": "123",
  "s3.credentials.provider.aws.access.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID",
  "s3.credentials.provider.aws.secret.access.key": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY",
  "transforms": "AddPrefix",
  "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.AddPrefix.regex": ".*",
  "transforms.AddPrefix.replacement": "copy_of_\$0"
}
EOF

sleep 10

log "Verifying topic copy_of_s3_topic"
playground topic consume --topic copy_of_s3_topic --min-expected-messages 9 --timeout 60
