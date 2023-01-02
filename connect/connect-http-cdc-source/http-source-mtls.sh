#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.mtls.yml"

log "Creating http-source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "com.github.castorm.kafka.connect.http.HttpSourceConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "http.request.url": "https://http-service-mtls-auth:8443/api/messages",
               "kafka.topic": "http-topic-messages",

               "http.client.keystore": "/tmp/keystore.http-service-mtls-auth.jks",
               "http.client.keystore.password": "confluent"
          }' \
     http://localhost:8083/connectors/http-cdc-source/config | jq .


sleep 3

log "Send a message to HTTP server"
curl --cert ./security/http-service-mtls-auth.certificate.pem --key ./security/http-service-mtls-auth.key --tlsv1.2 --cacert ./security/snakeoil-ca-1.crt  -X PUT \
     -H "Content-Type: application/json" \
     --data '{"test":"value"}' \
     https://localhost:8643/api/messages | jq .

# [2023-01-02 14:46:09,918] WARN [http-cdc-source|task-0] WorkerSourceTask{id=http-cdc-source-0} failed to poll records from SourceTask. Will retry operation. (org.apache.kafka.connect.runtime.AbstractWorkerSourceTask:472)
# org.apache.kafka.connect.errors.RetriableException: javax.net.ssl.SSLHandshakeException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
#         at com.github.castorm.kafka.connect.http.HttpSourceTask.execute(HttpSourceTask.java:128)
#         at com.github.castorm.kafka.connect.http.HttpSourceTask.poll(HttpSourceTask.java:109)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.poll(AbstractWorkerSourceTask.java:470)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.execute(AbstractWorkerSourceTask.java:349)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:256)
#         at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.run(AbstractWorkerSourceTask.java:75)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: javax.net.ssl.SSLHandshakeException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
#         at java.base/sun.security.ssl.Alert.createSSLException(Alert.java:131)
#         at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:353)
#         at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:296)
#         at java.base/sun.security.ssl.TransportContext.fatal(TransportContext.java:291)
#         at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.checkServerCerts(CertificateMessage.java:654)
#         at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.onCertificate(CertificateMessage.java:473)
#         at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.consume(CertificateMessage.java:369)
#         at java.base/sun.security.ssl.SSLHandshake.consume(SSLHandshake.java:392)
#         at java.base/sun.security.ssl.HandshakeContext.dispatch(HandshakeContext.java:443)
#         at java.base/sun.security.ssl.HandshakeContext.dispatch(HandshakeContext.java:421)
#         at java.base/sun.security.ssl.TransportContext.dispatch(TransportContext.java:183)
#         at java.base/sun.security.ssl.SSLTransport.decode(SSLTransport.java:172)
#         at java.base/sun.security.ssl.SSLSocketImpl.decode(SSLSocketImpl.java:1506)
#         at java.base/sun.security.ssl.SSLSocketImpl.readHandshakeRecord(SSLSocketImpl.java:1416)
#         at java.base/sun.security.ssl.SSLSocketImpl.startHandshake(SSLSocketImpl.java:456)
#         at java.base/sun.security.ssl.SSLSocketImpl.startHandshake(SSLSocketImpl.java:427)
#         at okhttp3.internal.connection.RealConnection.connectTls(RealConnection.kt:379)
#         at okhttp3.internal.connection.RealConnection.establishProtocol(RealConnection.kt:337)
#         at okhttp3.internal.connection.RealConnection.connect(RealConnection.kt:209)
#         at okhttp3.internal.connection.ExchangeFinder.findConnection(ExchangeFinder.kt:226)
#         at okhttp3.internal.connection.ExchangeFinder.findHealthyConnection(ExchangeFinder.kt:106)
#         at okhttp3.internal.connection.ExchangeFinder.find(ExchangeFinder.kt:74)
#         at okhttp3.internal.connection.RealCall.initExchange$okhttp(RealCall.kt:255)
#         at okhttp3.internal.connection.ConnectInterceptor.intercept(ConnectInterceptor.kt:32)
#         at okhttp3.internal.http.RealInterceptorChain.proceed(RealInterceptorChain.kt:109)
#         at okhttp3.internal.cache.CacheInterceptor.intercept(CacheInterceptor.kt:95)
#         at okhttp3.internal.http.RealInterceptorChain.proceed(RealInterceptorChain.kt:109)
#         at okhttp3.internal.http.BridgeInterceptor.intercept(BridgeInterceptor.kt:83)
#         at okhttp3.internal.http.RealInterceptorChain.proceed(RealInterceptorChain.kt:109)
#         at okhttp3.internal.http.RetryAndFollowUpInterceptor.intercept(RetryAndFollowUpInterceptor.kt:76)
#         at okhttp3.internal.http.RealInterceptorChain.proceed(RealInterceptorChain.kt:109)
#         at com.github.castorm.kafka.connect.http.client.okhttp.OkHttpClient.lambda$configure$0(OkHttpClient.java:70)
#         at okhttp3.internal.http.RealInterceptorChain.proceed(RealInterceptorChain.kt:109)
#         at okhttp3.logging.HttpLoggingInterceptor.intercept(HttpLoggingInterceptor.kt:154)
#         at okhttp3.internal.http.RealInterceptorChain.proceed(RealInterceptorChain.kt:109)
#         at okhttp3.internal.connection.RealCall.getResponseWithInterceptorChain$okhttp(RealCall.kt:201)
#         at okhttp3.internal.connection.RealCall.execute(RealCall.kt:154)
#         at com.github.castorm.kafka.connect.http.client.okhttp.OkHttpClient.execute(OkHttpClient.java:99)
#         at com.github.castorm.kafka.connect.http.HttpSourceTask.execute(HttpSourceTask.java:126)
#         ... 11 more
# Caused by: sun.security.validator.ValidatorException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
#         at java.base/sun.security.validator.PKIXValidator.doBuild(PKIXValidator.java:439)
#         at java.base/sun.security.validator.PKIXValidator.engineValidate(PKIXValidator.java:306)
#         at java.base/sun.security.validator.Validator.validate(Validator.java:264)
#         at java.base/sun.security.ssl.X509TrustManagerImpl.validate(X509TrustManagerImpl.java:313)
#         at java.base/sun.security.ssl.X509TrustManagerImpl.checkTrusted(X509TrustManagerImpl.java:222)
#         at java.base/sun.security.ssl.X509TrustManagerImpl.checkServerTrusted(X509TrustManagerImpl.java:129)
#         at java.base/sun.security.ssl.CertificateMessage$T12CertificateConsumer.checkServerCerts(CertificateMessage.java:638)
#         ... 45 more
# Caused by: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
#         at java.base/sun.security.provider.certpath.SunCertPathBuilder.build(SunCertPathBuilder.java:141)
#         at java.base/sun.security.provider.certpath.SunCertPathBuilder.engineBuild(SunCertPathBuilder.java:126)
#         at java.base/java.security.cert.CertPathBuilder.build(CertPathBuilder.java:297)
#         at java.base/sun.security.validator.PKIXValidator.doBuild(PKIXValidator.java:434)
#         ... 51 more

sleep 2

log "Verify we have received the data in http-topic-messages topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic http-topic-messages --from-beginning --property print.key=true --max-messages 1
