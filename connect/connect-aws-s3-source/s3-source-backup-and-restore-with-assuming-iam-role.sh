#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.backup-and-restore.with-assuming-iam-role.yml"

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
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
               "schema.compatibility": "NONE",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .

# [2022-11-09 08:36:47,871] ERROR Unable to read objects using the configured S3 credentials, bucket, and path. (io.confluent.connect.s3.source.S3SourceConnectorValidation:105)
# com.amazonaws.SdkClientException: Unable to load AWS credentials from any provider in the chain: [EnvironmentVariableCredentialsProvider: Unable to load AWS credentials from environment variables (AWS_ACCESS_KEY_ID (or AWS_ACCESS_KEY) and AWS_SECRET_KEY (or AWS_SECRET_ACCESS_KEY)), SystemPropertiesCredentialsProvider: Unable to load AWS credentials from Java system properties (aws.accessKeyId and aws.secretKey), WebIdentityTokenCredentialsProvider: class com.amazonaws.services.securitytoken.internal.STSProfileCredentialsService cannot be cast to class com.amazonaws.auth.profile.internal.securitytoken.ProfileCredentialsService (com.amazonaws.services.securitytoken.internal.STSProfileCredentialsService is in unnamed module of loader 'app'; com.amazonaws.auth.profile.internal.securitytoken.ProfileCredentialsService is in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @bff34c6), com.amazonaws.auth.profile.ProfileCredentialsProvider@151e92a3: class com.amazonaws.services.securitytoken.internal.STSProfileCredentialsService cannot be cast to class com.amazonaws.auth.profile.internal.securitytoken.ProfileCredentialsService (com.amazonaws.services.securitytoken.internal.STSProfileCredentialsService is in unnamed module of loader 'app'; com.amazonaws.auth.profile.internal.securitytoken.ProfileCredentialsService is in unnamed module of loader org.apache.kafka.connect.runtime.isolation.PluginClassLoader @bff34c6), com.amazonaws.auth.EC2ContainerCredentialsProviderWrapper@37ec24f5: The requested metadata is not found at http://169.254.169.254/latest/meta-data/iam/security-credentials/]
#         at com.amazonaws.auth.AWSCredentialsProviderChain.getCredentials(AWSCredentialsProviderChain.java:136)
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
#         at java.base/java.lang.Thread.run(Thread.java:829)

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


log "Verifying topic copy_of_s3_topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic copy_of_s3_topic --from-beginning --max-messages 9
