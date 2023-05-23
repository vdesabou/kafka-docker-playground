#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

LAMBDA_ROLE_NAME=pglambdarole$TAG
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME//[-._]/}

LAMBDA_FUNCTION_NAME=pglambdafunction$TAG
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
cd ../../connect/connect-aws-lambda-sink/my-add-function
rm -f add.zip
zip add.zip add.py
cp add.zip /tmp/
aws lambda create-function --function-name "$LAMBDA_FUNCTION_NAME" --zip-file fileb:///tmp/add.zip --handler add.lambda_handler --runtime python3.8 --role "$LAMBDA_ROLE"
cd -



${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.with-assuming-iam-role.yml"

log "Sending messages to topic add-topic"
seq -f "{\"a\": %g,\"b\": 1}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic add-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"a","type":"int"},{"name":"b","type":"int"}]}'

log "Creating AWS Lambda Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class" : "io.confluent.connect.aws.lambda.AwsLambdaSinkConnector",
               "tasks.max": "1",
               "topics" : "add-topic",
               "aws.lambda.function.name" : "'"$LAMBDA_FUNCTION_NAME"'",
               "aws.lambda.invocation.type" : "sync",
               "aws.lambda.batch.size" : "50",
               "aws.lambda.region": "'"$AWS_REGION"'",
               "behavior.on.error" : "fail",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-lambda/config | jq .


sleep 10

log "Verify topic success-responses"
playground topic consume --topic success-responses --expected-messages 10

# log "Verify topic error-responses"
playground topic consume --topic error-responses --expected-messages 1

log "Cleanup role and function"
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME