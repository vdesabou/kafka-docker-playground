#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $CONNECTOR_TAG "1.9.9"; then
    # skipped
    logwarn "WARN: skipped as it requires connector version 2.0.0"
    exit 111
fi

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
    exit 111
fi

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.generalized.repro-92390-connection-timed-out.yml"

AWS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}

AWS_REGION=$(aws configure get region | tr '\r' '\n')

log "Creating bucket name <$AWS_BUCKET_NAME>, if required"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME --recursive --region $AWS_REGION
set -e


log "Copy generalized.quickstart.json to bucket $AWS_BUCKET_NAME/quickstart"
aws s3 cp generalized.quickstart.json s3://$AWS_BUCKET_NAME/quickstart/generalized.quickstart.json

curl --request PUT \
  --url http://localhost:8083/admin/loggers/com.amazonaws \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

log "Creating Generalized S3 Source connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "confluent.license": "",
               "mode": "GENERIC",
               "topics.dir": "quickstart",
               "topic.regex.list": "quick-start-topic:.*",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/s3-source-generalized/config | jq .


log "Verifying topic quick-start-topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic quick-start-topic --from-beginning --max-messages 9

log "Block incoming traffic"
docker exec --privileged --user root connect bash -c "iptables -A INPUT -p tcp --sport 443 -j DROP"

# [2022-02-14 10:24:31,414] ERROR [s3-source-generalized|worker] WorkerConnector{id=s3-source-generalized} Connector raised an error (org.apache.kafka.connect.runtime.WorkerConnector:520)
# org.apache.kafka.connect.errors.ConnectException: Failed to list files in S3 bucket kafkadockerplaygroundbucketvsaboulin701 with path quickstart/ and continuation token null.
#         at io.confluent.connect.s3.source.S3Storage.listFiles(S3Storage.java:374)
#         at io.confluent.connect.s3.source.S3Storage.getObjectMetadata(S3Storage.java:196)
#         at io.confluent.connect.cloud.storage.source.GenericStorageSourceConnector.scanAndSortBucket(GenericStorageSourceConnector.java:238)
#         at io.confluent.connect.cloud.storage.source.GenericStorageSourceConnector.trackTaskProgress(GenericStorageSourceConnector.java:292)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.runAndReset(FutureTask.java:305)
#         at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:305)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.amazonaws.SdkClientException: Unable to execute HTTP request: Connect to s3.eu-west-3.amazonaws.com:443 [s3.eu-west-3.amazonaws.com/52.95.155.69] failed: connect timed out
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.handleRetryableException(AmazonHttpClient.java:1201)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeHelper(AmazonHttpClient.java:1147)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.doExecute(AmazonHttpClient.java:796)
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
#         at io.confluent.connect.s3.source.S3Storage.listFiles(S3Storage.java:366)
#         ... 9 more
# Caused by: org.apache.http.conn.ConnectTimeoutException: Connect to s3.eu-west-3.amazonaws.com:443 [s3.eu-west-3.amazonaws.com/52.95.155.69] failed: connect timed out
#         at org.apache.http.impl.conn.DefaultHttpClientConnectionOperator.connect(DefaultHttpClientConnectionOperator.java:151)
#         at org.apache.http.impl.conn.PoolingHttpClientConnectionManager.connect(PoolingHttpClientConnectionManager.java:376)
#         at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
#         at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
#         at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
#         at java.base/java.lang.reflect.Method.invoke(Method.java:566)
#         at com.amazonaws.http.conn.ClientConnectionManagerFactory$Handler.invoke(ClientConnectionManagerFactory.java:76)
#         at com.amazonaws.http.conn.$Proxy46.connect(Unknown Source)
#         at org.apache.http.impl.execchain.MainClientExec.establishRoute(MainClientExec.java:393)
#         at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:236)
#         at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#         at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.amazonaws.http.apache.client.impl.SdkHttpClient.execute(SdkHttpClient.java:72)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeOneRequest(AmazonHttpClient.java:1323)
#         at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeHelper(AmazonHttpClient.java:1139)
#         ... 21 more
# Caused by: java.net.SocketTimeoutException: connect timed out
#         at java.base/java.net.PlainSocketImpl.socketConnect(Native Method)
#         at java.base/java.net.AbstractPlainSocketImpl.doConnect(AbstractPlainSocketImpl.java:399)
#         at java.base/java.net.AbstractPlainSocketImpl.connectToAddress(AbstractPlainSocketImpl.java:242)
#         at java.base/java.net.AbstractPlainSocketImpl.connect(AbstractPlainSocketImpl.java:224)
#         at java.base/java.net.SocksSocketImpl.connect(SocksSocketImpl.java:392)
#         at java.base/java.net.Socket.connect(Socket.java:609)
#         at org.apache.http.conn.ssl.SSLConnectionSocketFactory.connectSocket(SSLConnectionSocketFactory.java:368)
#         at com.amazonaws.http.conn.ssl.SdkTLSSocketFactory.connectSocket(SdkTLSSocketFactory.java:142)
#         at org.apache.http.impl.conn.DefaultHttpClientConnectionOperator.connect(DefaultHttpClientConnectionOperator.java:142)
#         ... 37 more

