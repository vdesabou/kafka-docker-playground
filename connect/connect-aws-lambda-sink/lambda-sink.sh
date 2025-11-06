#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.0.12"
then
     logwarn "minimal supported connector version is 2.0.13 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

handle_aws_credentials

LAMBDA_ROLE_NAME=pg${USER}lambdabrole${GITHUB_RUN_NUMBER}${TAG_BASE}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME//[-._]/}

LAMBDA_FUNCTION_NAME=pg${USER}lambdafn${GITHUB_RUN_NUMBER}${TAG_BASE}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME//[-._]/}

set +e
log "Cleanup, this might fail..."
aws iam detach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME
set -e
log "Creating AWS role $LAMBDA_ROLE_NAME"
LAMBDA_ROLE=$(aws iam create-role --role-name $LAMBDA_ROLE_NAME --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' --tags Key=cflt_managed_by,Value=user Key=cflt_managed_id,Value="$USER" --output text --query 'Role.Arn')
if [ "$LAMBDA_ROLE" = "" ]
then
     logerror "Cannot create Lambda role"
     exit 1
fi
log "Sleeping 30 seconds to let the role being propagated by AWS"
sleep 30
log "Creating AWS Lambda function"
# https://docs.aws.amazon.com/lambda/latest/dg/python-package-create.html
cd ../../connect/connect-aws-lambda-sink/my-add-function
rm -f add.zip
zip add.zip add.py
cp add.zip /tmp/
aws lambda create-function --function-name "$LAMBDA_FUNCTION_NAME" --zip-file fileb:///tmp/add.zip --handler add.lambda_handler --runtime python3.8 --role "$LAMBDA_ROLE" --tags "cflt_managed_by=user,cflt_managed_id=$USER"
cd -

log "Attaching AWSLambdaBasicExecutionRole policy to $LAMBDA_ROLE_NAME (to be able to see logs in Cloudwatch)"
aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

function cleanup_cloud_resources {
  set +e
  log "Cleanup role and function"
  check_if_continue
  aws iam detach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam delete-role --role-name $LAMBDA_ROLE_NAME
  aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME
}
trap cleanup_cloud_resources EXIT

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic add-topic"
playground topic produce -t add-topic --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "a",
      "type": "int"
    },
    {
      "name": "b",
      "type": "int"
    }
  ]
}
EOF

log "Creating AWS Lambda Sink connector"
playground connector create-or-update --connector aws-lambda  << EOF
{
    "connector.class" : "io.confluent.connect.aws.lambda.AwsLambdaSinkConnector",
    "tasks.max": "1",
    "topics" : "add-topic",
    "aws.lambda.function.name" : "$LAMBDA_FUNCTION_NAME",
    "aws.lambda.invocation.type" : "sync",
    "aws.lambda.batch.size" : "50",
    "aws.lambda.region": "$AWS_REGION",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "behavior.on.error" : "fail",
    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.name": "error-responses",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.name": "success-responses",
    "reporter.result.topic.replication.factor": 1,
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF


sleep 10

log "Verify topic success-responses"
playground topic consume --topic success-responses --min-expected-messages 10 --timeout 60

# log "Verify topic error-responses"
playground topic consume --topic error-responses --min-expected-messages 0 --timeout 60