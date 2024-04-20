#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
then
     logerror "ERROR: either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
     exit 1
else
    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
    then
        log "💭 Using environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    else
        if [ -f $HOME/.aws/credentials ]
        then
            logwarn "💭 AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set based on $HOME/.aws/credentials"
            export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' )
            export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' ) 
        fi
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
fi

LAMBDA_ROLE_NAME=pg${USER}lambdabrole${TAG}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME//[-._]/}

LAMBDA_FUNCTION_NAME=pg${USER}lambdafn${TAG}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME//[-._]/}

set +e
log "Cleanup, this might fail..."
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME
set -e
log "Creating AWS role $LAMBDA_ROLE_NAME"
LAMBDA_ROLE=$(aws iam create-role --role-name $LAMBDA_ROLE_NAME --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' --output text --query 'Role.Arn')
if [ "$LAMBDA_ROLE" = "" ]
then
     logerror "Cannot create Lambda role"
     exit 1
fi

log "Sleeping 30 seconds to let the role being propagated by AWS"
sleep 30

log "Creating AWS Lambda function"
# https://docs.aws.amazon.com/lambda/latest/dg/python-package-create.html
cd ../../ccloud/fm-aws-lambda-sink/my-add-function
rm -f add.zip
zip add.zip add.py
cp add.zip /tmp/
aws lambda create-function --function-name "$LAMBDA_FUNCTION_NAME" --zip-file fileb:///tmp/add.zip --handler add.lambda_handler --runtime python3.8 --role "$LAMBDA_ROLE"
cd -


bootstrap_ccloud_environment

set +e
playground topic delete --topic add-topic
sleep 3
playground topic create --topic add-topic --nb-partitions 1
set -e

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

connector_name="LambdaSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "LambdaSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics" : "add-topic",
  "aws.lambda.configuration.mode": "single",
  "aws.lambda.function.name" : "$LAMBDA_FUNCTION_NAME",
  "aws.lambda.invocation.type" : "sync",
  "aws.lambda.region": "$AWS_REGION",
  "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
  "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
  "behavior.on.error": "fail",
  "input.data.format": "AVRO",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 10 --timeout 60

playground topic consume --topic error-$connectorId --min-expected-messages 0 --timeout 60

log "Cleanup role and function"
check_if_continue
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name