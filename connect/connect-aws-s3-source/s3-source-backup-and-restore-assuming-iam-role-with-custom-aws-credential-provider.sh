#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

logwarn "⚠️ This example and associated custom code is not supported, use at your own risks !"

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
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

for component in awscredentialsprovider
do
    set +e
    log "🏗 Building jar for ${component}"
    docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
    if [ $? != 0 ]
    then
        logerror "ERROR: failed to build java component "
        tail -500 /tmp/result.log
        exit 1
    fi
    set -e
done


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

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.backup-and-restore-assuming-iam-role-with-custom-aws-credential-provider.yml"

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
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "s3_topic",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "topics.dir": "'"$TAG"'",
               "s3.part.size": 5242880,
               "flush.size": "3",
               "s3.credentials.provider.class": "com.github.vdesabou.AwsAssumeRoleCredentialsProvider",
               "s3.credentials.provider.sts.role.arn": "'"$AWS_STS_ROLE_ARN"'",
               "s3.credentials.provider.sts.role.session.name": "session-name",
               "s3.credentials.provider.sts.role.external.id": "123",
               "s3.credentials.provider.sts.aws.access.key.id": "'"$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID"'",
               "s3.credentials.provider.sts.aws.secret.key.id": "'"$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY"'",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.compatibility": "NONE",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .


log "Sending messages to topic s3_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing objects of in S3"
aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp --only-show-errors s3://$AWS_BUCKET_NAME/$TAG/s3_topic/partition=0/s3_topic+0+0000000000.avro s3_topic+0+0000000000.avro

docker run --rm -v ${DIR}:/tmp vdesabou/avro-tools tojson /tmp/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro

log "Creating Backup and Restore S3 Source connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "topics.dir": "'"$TAG"'",
               "s3.credentials.provider.class": "com.github.vdesabou.AwsAssumeRoleCredentialsProvider",
               "s3.credentials.provider.sts.role.arn": "'"$AWS_STS_ROLE_ARN"'",
               "s3.credentials.provider.sts.role.session.name": "session-name",
               "s3.credentials.provider.sts.role.external.id": "123",
               "s3.credentials.provider.sts.aws.access.key.id": "'"$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_ACCESS_KEY_ID"'",
               "s3.credentials.provider.sts.aws.secret.key.id": "'"$AWS_ACCOUNT_WITH_ASSUME_ROLE_AWS_SECRET_ACCESS_KEY"'",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "transforms": "AddPrefix",
               "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.regex": ".*",
               "transforms.AddPrefix.replacement": "copy_of_$0"
          }' \
     http://localhost:8083/connectors/s3-source/config | jq .

# https://stackoverflow.com/a/64566641/2381999

# S3 sink: aws-java-sdk-core-1.12.268.jar 
# S3 source: aws-java-sdk-core-1.11.725.jar
# [2022-11-09 08:51:13,528] WARN /connectors/s3-source/config (org.eclipse.jetty.server.HttpChannel:776)
# javax.servlet.ServletException: org.glassfish.jersey.server.ContainerException: java.lang.NoSuchFieldError: ENDPOINT_OVERRIDDEN
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
#         at org.eclipse.jetty.util.thread.strategy.EatWhatYouKill.produce(EatWhatYouKill.java:137)
#         at org.eclipse.jetty.util.thread.QueuedThreadPool.runJob(QueuedThreadPool.java:883)
#         at org.eclipse.jetty.util.thread.QueuedThreadPool$Runner.run(QueuedThreadPool.java:1034)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.glassfish.jersey.server.ContainerException: java.lang.NoSuchFieldError: ENDPOINT_OVERRIDDEN
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
#         ... 34 more
# Caused by: java.lang.NoSuchFieldError: ENDPOINT_OVERRIDDEN
#         at com.amazonaws.services.securitytoken.AWSSecurityTokenServiceClient.executeAssumeRole(AWSSecurityTokenServiceClient.java:504)
#         at com.amazonaws.services.securitytoken.AWSSecurityTokenServiceClient.assumeRole(AWSSecurityTokenServiceClient.java:486)
#         at com.amazonaws.auth.STSAssumeRoleSessionCredentialsProvider.newSession(STSAssumeRoleSessionCredentialsProvider.java:343)
#         at com.amazonaws.auth.STSAssumeRoleSessionCredentialsProvider.access$000(STSAssumeRoleSessionCredentialsProvider.java:41)
#         at com.amazonaws.auth.STSAssumeRoleSessionCredentialsProvider$1.call(STSAssumeRoleSessionCredentialsProvider.java:90)
#         at com.amazonaws.auth.STSAssumeRoleSessionCredentialsProvider$1.call(STSAssumeRoleSessionCredentialsProvider.java:87)
#         at com.amazonaws.auth.RefreshableTask.refreshValue(RefreshableTask.java:257)
#         at com.amazonaws.auth.RefreshableTask.blockingRefresh(RefreshableTask.java:213)
#         at com.amazonaws.auth.RefreshableTask.getValue(RefreshableTask.java:154)
#         at com.amazonaws.auth.STSAssumeRoleSessionCredentialsProvider.getCredentials(STSAssumeRoleSessionCredentialsProvider.java:315)
#         at com.github.vdesabou.AwsAssumeRoleCredentialsProvider.getCredentials(AwsAssumeRoleCredentialsProvider.java:104)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.getCredentialsFromContext(AmazonHttpClient.java:1251)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.runBeforeRequestHandlers(AmazonHttpClient.java:827)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.doExecute(AmazonHttpClient.java:777)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeWithTimer(AmazonHttpClient.java:764)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.execute(AmazonHttpClient.java:738)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.access$500(AmazonHttpClient.java:698)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutionBuilderImpl.execute(AmazonHttpClient.java:680)
#         at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:544)
#         at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:524)
#         at com.amazonaws.services.s3.AmazonS3Client.invoke(AmazonS3Client.java:5052)
#         at com.amazonaws.services.s3.AmazonS3Client.invoke(AmazonS3Client.java:4998)
#         at com.amazonaws.services.s3.AmazonS3Client.invoke(AmazonS3Client.java:4992)
#         at com.amazonaws.services.s3.AmazonS3Client.listObjectsV2(AmazonS3Client.java:938)
#         at io.confluent.connect.s3.source.S3Storage.listUpToMaxObjects(S3Storage.java:127)
#         at io.confluent.connect.s3.source.S3SourceConnectorValidation.validateS3ReadPermissions(S3SourceConnectorValidation.java:98)
#         at io.confluent.connect.s3.source.S3SourceConnectorValidation.performValidation(S3SourceConnectorValidation.java:55)
#         at io.confluent.connect.utils.validators.all.ConfigValidation.validate(ConfigValidation.java:185)
#         at io.confluent.connect.cloud.storage.source.CompositeSourceConnector.validate(CompositeSourceConnector.java:101)
#         at org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:564)
#         at org.apache.kafka.connect.runtime.AbstractHerder.lambda$validateConnectorConfig$4(AbstractHerder.java:442)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         ... 1 more

log "Verifying topic copy_of_s3_topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic copy_of_s3_topic --from-beginning --max-messages 9
