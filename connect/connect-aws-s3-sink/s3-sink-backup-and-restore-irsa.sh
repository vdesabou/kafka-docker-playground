#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "10.5.99"
then
     logwarn "minimal supported connector version is 10.6.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

logwarn "⚠️ This example demonstrates IRSA (IAM Roles for Service Accounts) for EKS environments"
logwarn "⚠️ This example and associated custom code is not supported, use at your own risks!"

# For IRSA in EKS, these environment variables are automatically set by the EKS service account:
# - AWS_WEB_IDENTITY_TOKEN_FILE: Path to the service account token file
# - AWS_ROLE_ARN: The IAM role ARN associated with the service account
# - AWS_REGION: AWS region

# For this example, we'll simulate IRSA by setting these variables manually
# In a real EKS environment, these would be injected automatically by the mutating webhook

AWS_ROLE_ARN=${AWS_ROLE_ARN:-$1}

if [ -z "$AWS_ROLE_ARN" ]
then
     logerror "AWS_ROLE_ARN is not set. Export it as environment variable or pass it as argument"
     logerror "This should be the IAM role ARN associated with your EKS service account"
     exit 1
fi

# Optional: If you need to assume an additional role beyond the IRSA role
AWS_STS_ROLE_ARN=${AWS_STS_ROLE_ARN:-""}

log "Building jar for awscredentialsprovider-v2-irsa"
set +e
docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/awscredentialsprovider-v2-irsa":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/awscredentialsprovider-v2-irsa/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.9.11-eclipse-temurin-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
if [ $? != 0 ]
then
    logerror "Failed to build java component"
    tail -500 /tmp/result.log
    exit 1
fi
set -e
cp ${PWD}/awscredentialsprovider-v2-irsa/target/awscredentialsprovider-irsa-1.0.0-jar-with-dependencies.jar ../../confluent-hub/confluentinc-kafka-connect-s3/lib/awscredentialsprovider-irsa-1.0.0-jar-with-dependencies.jar


handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.backup-and-restore.irsa.yml"

AWS_BUCKET_NAME=pg-bucket-${USER}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}



log "Empty bucket <$AWS_BUCKET_NAME/$TAG>, if required"
set +e
if [ "$AWS_REGION" == "us-east-1" ]
then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
    aws s3api put-bucket-tagging --bucket $AWS_BUCKET_NAME --tagging "TagSet=[{Key=cflt_managed_by,Value=user},{Key=cflt_managed_id,Value=$USER}]"
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
    aws s3api put-bucket-tagging --bucket $AWS_BUCKET_NAME --tagging "TagSet=[{Key=cflt_managed_by,Value=user},{Key=cflt_managed_id,Value=$USER}]"
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
    "s3.credentials.provider.class": "com.github.vdesabou.AwsAssumeRoleIrsaCredentialsProvider",
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
