#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

${DIR}/../../environment/sasl-ssl/start.sh "${PWD}/docker-compose.plaintext.repro-proxy.yml"

KINESIS_STREAM_NAME=kafka_docker_playground$TAG
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME//[-.]/}

set +e
log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME
set -e

sleep 5

log "Create a Kinesis stream $KINESIS_STREAM_NAME"
aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1

log "Sleep 60 seconds to let the Kinesis stream being fully started"
sleep 60

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into kafka_docker_playground.
aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1

AWS_REGION=$(aws configure get region | tr '\r' '\n')

log "Creating Kinesis Source connector"
curl -X PUT \
     --cert ../../environment/sasl-ssl/security/connect.certificate.pem --key ../../environment/sasl-ssl/security/connect.key --tlsv1.2 --cacert ../../environment/sasl-ssl/security/snakeoil-ca-1.crt \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.stream": "'"$KINESIS_STREAM_NAME"'",
               "kinesis.region": "'"$AWS_REGION"'",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
               "confluent.topic.ssl.keystore.password" : "confluent",
               "confluent.topic.ssl.key.password" : "confluent",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.sasl.mechanism": "PLAIN",
               "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";"
          }' \
     https://localhost:8083/connectors/kinesis-source/config | jq .


# if not setting up java cacert in my trusttore as it is done here https://github.com/vdesabou/kafka-docker-playground/blob/af490e502fdbb899233011a272011c1cae48b9ab/environment/sasl-ssl/security/certs-create.sh#L76, I'm getting timeout and with SSL traces:
# javax.net.ssl|ERROR|3D|pool-2-thread-1|2021-03-29 15:59:44.501 UTC|TransportContext.java:341|Fatal (CERTIFICATE_UNKNOWN): PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target (
# "throwable" : {
#   sun.security.validator.ValidatorException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
#   	at java.base/sun.security.validator.PKIXValidator.doBuild(PKIXValidator.java:439)
#   	at java.base/sun.security.validator.PKIXValidator.engineValidate(PKIXValidator.java:306)
#   	at java.base/sun.security.validator.Validator.validate(Validator.java:264)
#   	at java.base/sun.security.ssl.X509TrustManagerImpl.validate(X509TrustManagerImpl.java:313)
#   	at java.base/sun.security.ssl.X509TrustManagerImpl.checkTrusted(X509TrustManagerImpl.java:222)
#   	at java.base/sun.security.ssl.X509TrustManagerImpl.checkServerTrusted(X509TrustManagerImpl.java:129)
#   	at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.checkServerCerts(CertificateMessage.java:638)
#   	at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.onCertificate(CertificateMessage.java:473)
#   	at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.consume(CertificateMessage.java:369)
#   	at java.base/sun.security.ssl.SSLHandshake.consume(SSLHandshake.java:392)
#   	at java.base/sun.security.ssl.HandshakeContext.dispatch(HandshakeContext.java:443)
#   	at java.base/sun.security.ssl.HandshakeContext.dispatch(HandshakeContext.java:421)
#   	at java.base/sun.security.ssl.TransportContext.dispatch(TransportContext.java:182)
#   	at java.base/sun.security.ssl.SSLTransport.decode(SSLTransport.java:171)
#   	at java.base/sun.security.ssl.SSLSocketImpl.decode(SSLSocketImpl.java:1408)
#   	at java.base/sun.security.ssl.SSLSocketImpl.readHandshakeRecord(SSLSocketImpl.java:1314)
#   	at java.base/sun.security.ssl.SSLSocketImpl.startHandshake(SSLSocketImpl.java:440)
#   	at java.base/sun.security.ssl.SSLSocketImpl.startHandshake(SSLSocketImpl.java:411)
#   	at org.apache.http.conn.ssl.SSLConnectionSocketFactory.createLayeredSocket(SSLConnectionSocketFactory.java:436)
#   	at org.apache.http.impl.conn.DefaultHttpClientConnectionOperator.upgrade(DefaultHttpClientConnectionOperator.java:191)
#   	at org.apache.http.impl.conn.PoolingHttpClientConnectionManager.upgrade(PoolingHttpClientConnectionManager.java:392)
#   	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
#   	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
#   	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
#   	at java.base/java.lang.reflect.Method.invoke(Method.java:566)
#   	at com.amazonaws.http.conn.ClientConnectionManagerFactory$Handler.invoke(ClientConnectionManagerFactory.java:76)
#   	at com.amazonaws.http.conn.$Proxy41.upgrade(Unknown Source)
#   	at org.apache.http.impl.execchain.MainClientExec.establishRoute(MainClientExec.java:428)
#   	at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:236)
#   	at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
#   	at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
#   	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#   	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#   	at com.amazonaws.http.apache.client.impl.SdkHttpClient.execute(SdkHttpClient.java:72)
#   	at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeOneRequest(AmazonHttpClient.java:1323)
#   	at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeHelper(AmazonHttpClient.java:1139)
#   	at com.amazonaws.http.AmazonHttpClient$RequestExecutor.doExecute(AmazonHttpClient.java:796)
#   	at com.amazonaws.http.AmazonHttpClient$RequestExecutor.executeWithTimer(AmazonHttpClient.java:764)
#   	at com.amazonaws.http.AmazonHttpClient$RequestExecutor.execute(AmazonHttpClient.java:738)
#   	at com.amazonaws.http.AmazonHttpClient$RequestExecutor.access$500(AmazonHttpClient.java:698)
#   	at com.amazonaws.http.AmazonHttpClient$RequestExecutionBuilderImpl.execute(AmazonHttpClient.java:680)
#   	at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:544)
#   	at com.amazonaws.http.AmazonHttpClient.execute(AmazonHttpClient.java:524)
#   	at com.amazonaws.services.kinesis.AmazonKinesisClient.doInvoke(AmazonKinesisClient.java:2809)
#   	at com.amazonaws.services.kinesis.AmazonKinesisClient.invoke(AmazonKinesisClient.java:2776)
#   	at com.amazonaws.services.kinesis.AmazonKinesisClient.invoke(AmazonKinesisClient.java:2765)
#   	at com.amazonaws.services.kinesis.AmazonKinesisClient.executeListStreams(AmazonKinesisClient.java:1699)
#   	at com.amazonaws.services.kinesis.AmazonKinesisClient.listStreams(AmazonKinesisClient.java:1670)
#   	at com.amazonaws.services.kinesis.AmazonKinesisClient.listStreams(AmazonKinesisClient.java:1711)
#   	at io.confluent.connect.kinesis.Validations.validateAndCreateClient(Validations.java:113)
#   	at io.confluent.connect.kinesis.Validations.validateAll(Validations.java:54)
#   	at io.confluent.connect.utils.validators.all.ConfigValidation.lambda$callValidators$0(ConfigValidation.java:222)
#   	at java.base/java.util.Spliterators$ArraySpliterator.forEachRemaining(Spliterators.java:948)
#   	at java.base/java.util.stream.ReferencePipeline$Head.forEach(ReferencePipeline.java:658)
#   	at io.confluent.connect.utils.validators.all.ConfigValidation.callValidators(ConfigValidation.java:222)
#   	at io.confluent.connect.utils.validators.all.ConfigValidation.validate(ConfigValidation.java:182)
#   	at io.confluent.connect.kinesis.KinesisSourceConnector.validate(KinesisSourceConnector.java:112)
#   	at org.apache.kafka.connect.runtime.AbstractHerder.validateConnectorConfig(AbstractHerder.java:378)
#   	at org.apache.kafka.connect.runtime.AbstractHerder.lambda$validateConnectorConfig$1(AbstractHerder.java:326)
#   	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#   	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#   	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#   	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#   	at java.base/java.lang.Thread.run(Thread.java:834)
#   Caused by: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
#   	at java.base/sun.security.provider.certpath.SunCertPathBuilder.build(SunCertPathBuilder.java:141)
#   	at java.base/sun.security.provider.certpath.SunCertPathBuilder.engineBuild(SunCertPathBuilder.java:126)
#   	at java.base/java.security.cert.CertPathBuilder.build(CertPathBuilder.java:297)
#   	at java.base/sun.security.validator.PKIXValidator.doBuild(PKIXValidator.java:434)
#   	... 63 more}

# )


log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --consumer.config /etc/kafka/secrets/client_without_interceptors.config --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME