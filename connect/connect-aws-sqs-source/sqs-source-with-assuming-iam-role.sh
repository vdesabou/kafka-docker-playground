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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.with-assuming-iam-role.yml"

QUEUE_NAME=pg${USER}sqs${TAG}
QUEUE_NAME=${QUEUE_NAME//[-._]/}

QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(echo "$QUEUE_URL_RAW" | cut -d "/" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     log "Sleeping 60 seconds"
     sleep 60
fi
set -e

log "Create a FIFO queue $QUEUE_NAME"
aws sqs create-queue --queue-name $QUEUE_NAME

log "Sending messages to $QUEUE_URL"
cd ../../connect/connect-aws-sqs-source
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json
cd -

log "Creating SQS Source connector"
playground connector create-or-update --connector sqs-source  << EOF
{
     "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
     "tasks.max": "1",
     "kafka.topic": "test-sqs-source",
     "sqs.url": "$QUEUE_URL",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "errors.tolerance": "all",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF


# [2023-07-24 13:18:40,240] ERROR Could not connect to your Amazon SQS queue (io.confluent.connect.sqs.source.SqsSourceConfigValidation:174)
# software.amazon.awssdk.core.exception.SdkClientException: Unable to load credentials from any of the providers in the chain AwsCredentialsProviderChain(credentialsProviders=[SystemPropertyCredentialsProvider(), EnvironmentVariableCredentialsProvider(), WebIdentityTokenCredentialsProvider(), ProfileCredentialsProvider(profileName=default, profileFile=ProfileFile(profilesAndSectionsMap=[{default=Profile(name=default, properties=[source_profile, role_arn, role_session_name]), cc-staging-1=Profile(name=cc-staging-1, properties=[output, aws_access_key_id, aws_secret_access_key])}, {}])), ContainerCredentialsProvider(), InstanceProfileCredentialsProvider()]) : [SystemPropertyCredentialsProvider(): Unable to load credentials from system settings. Access key must be specified either via environment variable (AWS_ACCESS_KEY_ID) or system property (aws.accessKeyId)., EnvironmentVariableCredentialsProvider(): Unable to load credentials from system settings. Access key must be specified either via environment variable (AWS_ACCESS_KEY_ID) or system property (aws.accessKeyId)., WebIdentityTokenCredentialsProvider(): Either the environment variable AWS_WEB_IDENTITY_TOKEN_FILE or the javaproperty aws.webIdentityTokenFile must be set., ProfileCredentialsProvider(profileName=default, profileFile=ProfileFile(profilesAndSectionsMap=[{default=Profile(name=default, properties=[source_profile, role_arn, role_session_name]), cc-staging-1=Profile(name=cc-staging-1, properties=[output, aws_access_key_id, aws_secret_access_key])}, {}])): To use assumed roles in the 'default' profile, the 'sts' service module must be on the class path., ContainerCredentialsProvider(): Cannot fetch credentials from container - neither AWS_CONTAINER_CREDENTIALS_FULL_URI or AWS_CONTAINER_CREDENTIALS_RELATIVE_URI environment variables are set., InstanceProfileCredentialsProvider(): Failed to load credentials from IMDS.]
# 	at software.amazon.awssdk.core.exception.SdkClientException$BuilderImpl.build(SdkClientException.java:111)
# 	at software.amazon.awssdk.auth.credentials.AwsCredentialsProviderChain.resolveCredentials(AwsCredentialsProviderChain.java:117)
# 	at software.amazon.awssdk.auth.credentials.internal.LazyAwsCredentialsProvider.resolveCredentials(LazyAwsCredentialsProvider.java:45)
# 	at software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider.resolveCredentials(DefaultCredentialsProvider.java:128)
# 	at software.amazon.awssdk.core.internal.util.MetricUtils.measureDuration(MetricUtils.java:50)
# 	at software.amazon.awssdk.awscore.internal.authcontext.AwsCredentialsAuthorizationStrategy.resolveCredentials(AwsCredentialsAuthorizationStrategy.java:100)
# 	at software.amazon.awssdk.awscore.internal.authcontext.AwsCredentialsAuthorizationStrategy.addCredentialsToExecutionAttributes(AwsCredentialsAuthorizationStrategy.java:77)
# 	at software.amazon.awssdk.awscore.internal.AwsExecutionContextBuilder.invokeInterceptorsAndCreateExecutionContext(AwsExecutionContextBuilder.java:123)
# 	at software.amazon.awssdk.awscore.client.handler.AwsAsyncClientHandler.invokeInterceptorsAndCreateExecutionContext(AwsAsyncClientHandler.java:65)
# 	at software.amazon.awssdk.core.internal.handler.BaseAsyncClientHandler.lambda$execute$1(BaseAsyncClientHandler.java:77)
# 	at software.amazon.awssdk.core.internal.handler.BaseAsyncClientHandler.measureApiCallSuccess(BaseAsyncClientHandler.java:291)
# 	at software.amazon.awssdk.core.internal.handler.BaseAsyncClientHandler.execute(BaseAsyncClientHandler.java:75)
# 	at software.amazon.awssdk.awscore.client.handler.AwsAsyncClientHandler.execute(AwsAsyncClientHandler.java:52)
# 	at software.amazon.awssdk.services.sqs.DefaultSqsAsyncClient.receiveMessage(DefaultSqsAsyncClient.java:1601)
# 	at io.confluent.connect.sqs.source.SqsSourceConfigValidation.checkReceiveMessagePermission(SqsSourceConfigValidation.java:120)
# 	at io.confluent.connect.sqs.source.SqsSourceConfigValidation.performValidation(SqsSourceConfigValidation.java:101)
# 	at io.confluent.connect.utils.validators.all.ConfigValidation.validate(ConfigValidation.java:185)
# 	at io.confluent.connect.sqs.source.SqsSourceConnector.validate(SqsSourceConnector.java:80)
# 	at org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:571)
# 	at org.apache.kafka.connect.runtime.AbstractHerder.lambda$validateConnectorConfig$4(AbstractHerder.java:449)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)


log "Verify we have received the data in test-sqs-source topic"
playground topic consume --topic test-sqs-source --min-expected-messages 2 --timeout 60

log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
