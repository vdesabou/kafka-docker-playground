#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

logwarn "⚠️ This example and associated custom code is not supported, use at your own risks !"

export COMPONENT_NAME="awscredentialsprovider"
if version_gt $CONNECTOR_TAG "1.9.9"
then
    export COMPONENT_NAME="awscredentialsprovider-v2"
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

for component in $COMPONENT_NAME
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${PWD}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "$PWD/../../scripts/settings.xml:/tmp/settings.xml" -v "${PWD}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -s /tmp/settings.xml -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "❌ failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.assuming-iam-role-with-custom-aws-credential-provider.yml"

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
     aws sqs delete-queue --queue-url ${QUEUE_URL}
fi
set -e

log "Create a FIFO queue $QUEUE_NAME"
aws sqs create-queue --queue-name $QUEUE_NAME

function cleanup_cloud_resources {
    set +e
    log "Delete SQS queue ${QUEUE_NAME}"
    check_if_continue
    aws sqs delete-queue --queue-url ${QUEUE_URL}
}
trap cleanup_cloud_resources EXIT

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
    "sqs.credentials.provider.class": "com.github.vdesabou.AwsAssumeRoleCredentialsProvider",
    "sqs.credentials.provider.sts.role.arn": "$AWS_STS_ROLE_ARN",
    "sqs.credentials.provider.sts.role.session.name": "session-name",
    "sqs.credentials.provider.sts.role.external.id": "123",
    "_sqs.credentials.provider.sts.aws.access.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID",
    "_sqs.credentials.provider.sts.aws.secret.key.id": "$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

log "Verify we have received the data in test-sqs-source topic"
playground topic consume --topic test-sqs-source --min-expected-messages 2 --timeout 60


# [2025-03-21 09:11:30,583] WARN /connectors/sqs-source/config (org.eclipse.jetty.server.HttpChannel:776)
# javax.servlet.ServletException: org.glassfish.jersey.server.ContainerException: java.lang.IllegalAccessError: class software.amazon.awssdk.awscore.client.builder.AwsDefaultClientBuilder tried to access private field software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder.overrideConfig (software.amazon.awssdk.awscore.client.builder.AwsDefaultClientBuilder and software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder are in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @5f7b97da)
#         at org.glassfish.jersey.servlet.WebComponent.serviceImpl(WebComponent.java:410)
#         at org.glassfish.jersey.servlet.WebComponent.service(WebComponent.java:346)
#         at org.glassfish.jersey.servlet.ServletContainer.service(ServletContainer.java:358)
#         at org.glassfish.jersey.servlet.ServletContainer.service(ServletContainer.java:311)
#         at org.glassfish.jersey.servlet.ServletContainer.service(ServletContainer.java:205)
#         at org.eclipse.jetty.servlet.ServletHolder.handle(ServletHolder.java:799)
#         at org.eclipse.jetty.servlet.ServletHandler.doHandle(ServletHandler.java:554)
#         at org.eclipse.jetty.server.handler.ScopedHandler.nextHandle(ScopedHandler.java:233)
#         at org.eclipse.jetty.server.session.SessionHandler.doHandle(SessionHandler.java:1624)
#         at org.eclipse.jetty.server.handler.ScopedHandler.nextHandle(ScopedHandler.java:233)
#         at org.eclipse.jetty.server.handler.ContextHandler.doHandle(ContextHandler.java:1440)
#         at org.eclipse.jetty.server.handler.ScopedHandler.nextScope(ScopedHandler.java:188)
#         at org.eclipse.jetty.servlet.ServletHandler.doScope(ServletHandler.java:505)
#         at org.eclipse.jetty.server.session.SessionHandler.doScope(SessionHandler.java:1594)
#         at org.eclipse.jetty.server.handler.ScopedHandler.nextScope(ScopedHandler.java:186)
#         at org.eclipse.jetty.server.handler.ContextHandler.doScope(ContextHandler.java:1355)
#         at org.eclipse.jetty.server.handler.ScopedHandler.handle(ScopedHandler.java:141)
#         at org.eclipse.jetty.server.handler.ContextHandlerCollection.handle(ContextHandlerCollection.java:234)
#         at org.eclipse.jetty.server.handler.StatisticsHandler.handle(StatisticsHandler.java:181)
#         at org.eclipse.jetty.server.handler.HandlerWrapper.handle(HandlerWrapper.java:127)
#         at org.eclipse.jetty.server.Server.handle(Server.java:516)
#         at org.eclipse.jetty.server.HttpChannel.lambda$handle$1(HttpChannel.java:487)
#         at org.eclipse.jetty.server.HttpChannel.dispatch(HttpChannel.java:732)
#         at org.eclipse.jetty.server.HttpChannel.handle(HttpChannel.java:479)
#         at org.eclipse.jetty.server.HttpConnection.onFillable(HttpConnection.java:277)
#         at org.eclipse.jetty.io.AbstractConnection$ReadCallback.succeeded(AbstractConnection.java:311)
#         at org.eclipse.jetty.io.FillInterest.fillable(FillInterest.java:105)
#         at org.eclipse.jetty.io.ChannelEndPoint$1.run(ChannelEndPoint.java:104)
#         at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.runTask(EatWhatYouKill.java:338)
#         at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.doProduce(EatWhatYouKill.java:315)
#         at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.tryProduce(EatWhatYouKill.java:173)
#         at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.run(EatWhatYouKill.java:131)
#         at org.eclipse.jetty.util.thread.ReservedThreadExecutor$ReservedThread.run(ReservedThreadExecutor.java:409)
#         at org.eclipse.jetty.util.thread.QueuedThreadPool.runJob(QueuedThreadPool.java:883)
#         at org.eclipse.jetty.util.thread.QueuedThreadPool$Runner.run(QueuedThreadPool.java:1034)
#         at java.base/java.lang.Thread.run(Unknown Source)
# Caused by: org.glassfish.jersey.server.ContainerException: java.lang.IllegalAccessError: class software.amazon.awssdk.awscore.client.builder.AwsDefaultClientBuilder tried to access private field software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder.overrideConfig (software.amazon.awssdk.awscore.client.builder.AwsDefaultClientBuilder and software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder are in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @5f7b97da)
#         at org.glassfish.jersey.servlet.internal.ResponseWriter.rethrow(ResponseWriter.java:255)
#         at org.glassfish.jersey.servlet.internal.ResponseWriter.failure(ResponseWriter.java:237)
#         at org.glassfish.jersey.server.ServerRuntime$Responder.process(ServerRuntime.java:438)
#         at org.glassfish.jersey.server.ServerRuntime$1.run(ServerRuntime.java:263)
#         at org.glassfish.jersey.internal.Errors$1.call(Errors.java:248)
#         at org.glassfish.jersey.internal.Errors$1.call(Errors.java:244)
#         at org.glassfish.jersey.internal.Errors.process(Errors.java:292)
#         at org.glassfish.jersey.internal.Errors.process(Errors.java:274)
#         at org.glassfish.jersey.internal.Errors.process(Errors.java:244)
#         at org.glassfish.jersey.process.internal.RequestScope.runInScope(RequestScope.java:265)
#         at org.glassfish.jersey.server.ServerRuntime.process(ServerRuntime.java:234)
#         at org.glassfish.jersey.server.ApplicationHandler.handle(ApplicationHandler.java:684)
#         at org.glassfish.jersey.servlet.WebComponent.serviceImpl(WebComponent.java:394)
#         ... 35 more
# Caused by: java.lang.IllegalAccessError: class software.amazon.awssdk.awscore.client.builder.AwsDefaultClientBuilder tried to access private field software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder.overrideConfig (software.amazon.awssdk.awscore.client.builder.AwsDefaultClientBuilder and software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder are in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @5f7b97da)
#         at software.amazon.awssdk.awscore.client.builder.AwsDefaultClientBuilder.setOverrides(AwsDefaultClientBuilder.java:205)
#         at software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder.asyncClientConfiguration(SdkDefaultClientBuilder.java:212)
#         at software.amazon.awssdk.services.sqs.DefaultSqsAsyncClientBuilder.buildClient(DefaultSqsAsyncClientBuilder.java:37)
#         at software.amazon.awssdk.services.sqs.DefaultSqsAsyncClientBuilder.buildClient(DefaultSqsAsyncClientBuilder.java:25)
#         at software.amazon.awssdk.core.client.builder.SdkDefaultClientBuilder.build(SdkDefaultClientBuilder.java:155)
#         at io.confluent.connect.sqs.util.SqsClientUtil.createAsyncClient(SqsClientUtil.java:46)
#         at io.confluent.connect.sqs.source.SqsSourceConfigValidation.performValidation(SqsSourceConfigValidation.java:89)
#         at io.confluent.connect.utils.validators.all.ConfigValidation.validate(ConfigValidation.java:185)
#         at io.confluent.connect.sqs.source.SqsSourceConnector.validate(SqsSourceConnector.java:80)
#         at org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:745)
#         at org.apache.kafka.connect.runtime.AbstractHerder.lambda$validateConnectorConfig$5(AbstractHerder.java:597)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Unknown Source)
#         at java.base/java.util.concurrent.FutureTask.run(Unknown Source)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(Unknown Source)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(Unknown Source)
#         ... 1 more