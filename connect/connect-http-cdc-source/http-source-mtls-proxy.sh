#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh


playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.mtls-proxy.yml"

log "Creating http-source connector"
playground connector create-or-update --connector http-cdc-sourc2e << EOF
{
     "tasks.max": "1",
     "connector.class": "com.github.castorm.kafka.connect.http.HttpSourceConnector",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "http.request.url": "https://http-service-mtls-auth:8443/api/messages",
     "kafka.topic": "http-topic-messages",

     "http.client.keystore": "/tmp/keystore.http-service-mtls-auth.p12",
     "http.client.keystore.password": "confluent"
}
EOF


sleep 3

log "Send a message to HTTP server"
curl --cert ../../connect/connect-http-sink/security/http-service-mtls-auth.certificate.pem --key ../../connect/connect-http-sink/security/http-service-mtls-auth.key --tlsv1.2 --cacert ../../connect/connect-http-sink/security/snakeoil-ca-1.crt  -X PUT \
     -H "Content-Type: application/json" \
     --data '{"test":"value"}' \
     https://localhost:8643/api/messages | jq .


sleep 2

log "Verify we have received the data in http-topic-messages topic"
playground topic consume --topic http-topic-messages --min-expected-messages 1 --timeout 60


# [2023-01-09 10:27:55,251] WARN [http-cdc-sourc2e|task-0] WorkerSourceTask{id=http-cdc-sourc2e-0} failed to poll records from SourceTask. Will retry operation. (org.apache.kafka.connect.runtime.AbstractWorkerSourceTask:472)
# org.apache.kafka.connect.errors.RetriableException: java.io.IOException: Unexpected response code for CONNECT: 400
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
# Caused by: java.io.IOException: Unexpected response code for CONNECT: 400
#         at okhttp3.internal.connection.RealConnection.createTunnel(RealConnection.kt:483)
#         at okhttp3.internal.connection.RealConnection.connectTunnel(RealConnection.kt:262)
#         at okhttp3.internal.connection.RealConnection.connect(RealConnection.kt:201)
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
exit 0

docker exec -d --privileged --user root connect bash -c 'tcpdump -w /tmp/tcpdump.pcap -i eth0 -s 0'
