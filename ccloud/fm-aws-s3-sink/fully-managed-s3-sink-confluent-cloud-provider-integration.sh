#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

S3_PROVIDER_INTEGRATION_ID=${S3_PROVIDER_INTEGRATION_ID:-$1}

if [ -z "$S3_PROVIDER_INTEGRATION_ID" ]
then
     logerror "S3_PROVIDER_INTEGRATION_ID is not set. Export it as environment variable or pass it as argument"
     logerror "follow steps in https://docs.confluent.io/cloud/current/connectors/provider-integration/index.html"
     exit 1
fi

handle_aws_credentials

bootstrap_ccloud_environment

set +e
playground topic delete --topic s3_topic
sleep 3
playground topic create --topic s3_topic --nb-partitions 1
set -e

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

log "Creating s3_topic topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic create --topic s3_topic
set -e

log "Sending messages to topic s3_topic"
playground topic produce -t s3_topic --nb-messages 1000 --forced-value '{"f1":"value%g"}' << 'EOF'
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

connector_name="S3_SINK_CPI_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "S3_SINK",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "s3_topic",
    "topics.dir": "$TAG",
    "authentication.method":"IAM Roles",
    "provider.integration.id":"$S3_PROVIDER_INTEGRATION_ID",
    "input.data.format": "AVRO",
    "output.data.format": "AVRO",
    "s3.bucket.name": "$AWS_BUCKET_NAME",
    "s3.region":"$AWS_REGION",
    "time.interval" : "HOURLY",
    "flush.size": "1000",
    "schema.compatibility": "NONE",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

# log "Listing objects of in S3"
# aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp --only-show-errors --recursive s3://$AWS_BUCKET_NAME/$TAG/s3_topic /tmp/s3_topic

cp /tmp/s3_topic/*/*/*/*/s3_topic+0+0000000000.avro /tmp/s3_topic+0+0000000000.avro

playground  tools read-avro-file --file /tmp/s3_topic+0+0000000000.avro | grep value999

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name