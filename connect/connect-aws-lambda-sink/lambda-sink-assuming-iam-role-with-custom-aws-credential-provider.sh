#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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
            export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials| awk -F'=' '{print $2;}' )
            export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials| awk -F'=' '{print $2;}' ) 
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


for component in awscredentialsprovider
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

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



${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.backup-and-restore-assuming-iam-role-with-custom-aws-credential-provider.yml"

log "Sending messages to topic add-topic"
seq -f "{\"a\": %g,\"b\": 1}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic add-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"a","type":"int"},{"name":"b","type":"int"}]}'

log "Creating AWS Lambda Sink connector"
playground connector create-or-update --connector aws-lambda << EOF
{
               "connector.class" : "io.confluent.connect.aws.lambda.AwsLambdaSinkConnector",
               "tasks.max": "1",
               "topics" : "add-topic",
               "aws.lambda.function.name" : "$LAMBDA_FUNCTION_NAME",
               "aws.lambda.invocation.type" : "sync",
               "aws.lambda.batch.size" : "50",
               "aws.lambda.region": "$AWS_REGION",

               "aws.credentials.provider.class": "com.github.vdesabou.AwsAssumeRoleCredentialsProvider",
               "aws.credentials.provider.sts.role.arn": "$AWS_STS_ROLE_ARN",
               "aws.credentials.provider.sts.role.session.name": "session-name",
               "aws.credentials.provider.sts.role.external.id": "123",
               "aws.credentials.provider.sts.aws.access.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID",
               "aws.credentials.provider.sts.aws.secret.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY",
               
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

log "Cleanup role and function"
aws iam delete-role --role-name $LAMBDA_ROLE_NAME
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME