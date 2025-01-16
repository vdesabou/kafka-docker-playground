#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh



handle_aws_credentials

bootstrap_ccloud_environment

set +e
playground topic delete --topic quick-start-topic
sleep 3
playground topic create --topic quick-start-topic --nb-partitions 1
set -e

AWS_BUCKET_NAME=pg-bucket-${USER}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}


log "Create bucket <$AWS_BUCKET_NAME>, if required"
set +e
if [ "$AWS_REGION" == "us-east-1" ]
then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
set -e
log "Empty bucket <$AWS_BUCKET_NAME/quickstart>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME/quickstart --recursive --region $AWS_REGION
set -e

cd ../../ccloud/fm-aws-s3-source
log "Copy generalized.quickstart.json to bucket $AWS_BUCKET_NAME/quickstart"
aws s3 cp generalized.quickstart.json s3://$AWS_BUCKET_NAME/quickstart/generalized.quickstart.json
cd -

connector_name="S3Source_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "S3Source",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics.dir": "quickstart",
    "topic.regex.list": "quick-start-topic:.*",
    "s3.region": "$AWS_REGION",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "input.data.format": "JSON",
    "output.data.format": "JSON",
    "s3.bucket.name": "$AWS_BUCKET_NAME",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 30

log "Verifying topic quick-start-topic"
playground topic consume --topic quick-start-topic --min-expected-messages 9 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name