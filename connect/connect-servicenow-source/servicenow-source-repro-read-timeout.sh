#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_end_of_hibernation () {
     MAX_WAIT=1200
     CUR_WAIT=0
     log "Waiting up to $MAX_WAIT seconds for end of hibernation to happen (it can take several minutes)"
     curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
     while [[ $(cat /tmp/out.txt) =~ "Sign in to the site to wake your instance" ]]
     do
          sleep 10
          curl -X POST "${SERVICENOW_URL}/api/now/table/incident" --user admin:"$SERVICENOW_PASSWORD" -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'cache-control: no-cache' -d '{"short_description": "This is test"}' > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs still show 'Sign in to the site to wake your instance' after $MAX_WAIT seconds.\n"
               exit 1
          fi
     done
     log "The instance is ready !"
}

SERVICENOW_URL=${SERVICENOW_URL:-$1}
SERVICENOW_PASSWORD=${SERVICENOW_PASSWORD:-$2}

if [ -z "$SERVICENOW_URL" ]
then
     logerror "SERVICENOW_URL is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [[ "$SERVICENOW_URL" != */ ]]
then
    logerror "SERVICENOW_URL does not end with "/" Example: https://dev12345.service-now.com/ "
    exit 1
fi

if [ -z "$SERVICENOW_PASSWORD" ]
then
     logerror "SERVICENOW_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ ! -z "$CI" ]
then
     # this is github actions
     set +e
     log "Waking up servicenow instance..."
     docker run -e USERNAME="$SERVICENOW_DEVELOPER_USERNAME" -e PASSWORD="$SERVICENOW_DEVELOPER_PASSWORD" ruthless/servicenow-instance-wakeup:latest
     set -e
     wait_for_end_of_hibernation
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-read-timeout.yml"

export HTTP_PROXY=127.0.0.1:8888
export HTTPS_PROXY=127.0.0.1:8888
log "Verify forward proxy is working correctly"
curl --compressed -H 'Accept-Encoding: gzip' -H 'Content-Type: application/json' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u "admin:$SERVICENOW_PASSWORD" | jq .

docker exec -e SERVICENOW_URL=$SERVICENOW_URL -e SERVICENOW_PASSWORD=$SERVICENOW_PASSWORD connect bash -c "export HTTP_PROXY=nginx_proxy:8888 && export HTTPS_PROXY=nginx_proxy:8888 && curl --compressed -H 'Accept-Encoding: gzip' -H 'User-Agent: Google-HTTP-Java-Client/1.30.0 (gzip)' -v ${SERVICENOW_URL}api/now/table/incident?sysparm_limit=1 -u \"admin:$SERVICENOW_PASSWORD\""

# block
# echo "$SERVICENOW_URL" | cut -d "/" -f3
# ip=$(dig +short $(echo "$SERVICENOW_URL" | cut -d "/" -f3))
# log "Blocking serviceNow instance IP address $ip on connect, to make sure proxy is used"
# docker exec -i --privileged --user root connect bash -c "yum update -y && yum install iptables -y"
# docker exec -i --privileged --user root connect bash -c "iptables -A INPUT -s $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -A INPUT -d $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -A OUTPUT -s $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -A OUTPUT -d $ip -j REJECT"
# docker exec -i --privileged --user root connect bash -c "iptables -L -n -v"

TODAY=$(date '+%Y-%m-%d')

log "Creating ServiceNow Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.servicenow.ServiceNowSourceConnector",
               "kafka.topic": "topic-servicenow",
               "proxy.url": "nginx_proxy:8888",
               "servicenow.url": "'"$SERVICENOW_URL"'",
               "tasks.max": "1",
               "servicenow.table": "incident",
               "servicenow.user": "admin",
               "servicenow.password": "'"$SERVICENOW_PASSWORD"'",
               "servicenow.since": "'"$TODAY"'",
               "key.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/servicenow-source/config | jq .


sleep 10

log "Create one record to ServiceNow using proxy"
docker exec -e SERVICENOW_URL="$SERVICENOW_URL" -e SERVICENOW_PASSWORD="$SERVICENOW_PASSWORD" connect bash -c "export HTTP_PROXY=nginx_proxy:8888 && export HTTPS_PROXY=nginx_proxy:8888 && \
   curl -X POST \
    \"${SERVICENOW_URL}api/now/table/incident\" \
    --user admin:\"$SERVICENOW_PASSWORD\" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{\"short_description\": \"This is test\"}'"

sleep 5

log "Verify we have received the data in topic-servicenow topic"
timeout 60 docker exec connect kafka-console-consumer -bootstrap-server broker:9092 --topic topic-servicenow --from-beginning --max-messages 1

log "Adding latency from nginx_proxy to connect to simulate a read timeout (hard-coded to 20 seconds)"
# connect
latency_put=$(get_latency nginx_proxy connect)
log "Latency from nginx_proxy to nginx_proxy BEFORE traffic control: $latency_put ms"

add_latency nginx_proxy connect 6000ms

latency_put=$(get_latency nginx_proxy connect)
log "Latency from nginx_proxy to nginx_proxy AFTER traffic control: $latency_put ms"



# with 2.1.1, no retry:
# Aug 02, 2021 3:16:34 PM com.google.api.client.http.HttpResponse <init>
# CONFIG: -------------- RESPONSE --------------
# HTTP/1.1 200 OK
# X-Is-Logged-In: true
# X-Transaction-ID: ab142c282f35
# Set-Cookie: glide_session_store=B20424282F3530104318FE1DF699B63D; Max-Age=60; Expires=Mon, 02-Aug-2021 15:17:34 GMT; Path=/; HttpOnly;Secure
# X-Total-Count: 1
# Pragma: no-store,no-cache
# Cache-Control: no-cache,no-store,must-revalidate,max-age=-1
# Expires: 0
# Content-Type: application/json;charset=UTF-8
# Transfer-Encoding: chunked
# Date: Mon, 02 Aug 2021 15:16:33 GMT
# Server: ServiceNow
# Strict-Transport-Security: max-age=63072000; includeSubDomains

# [2021-08-02 15:16:54,084] INFO [servicenow-source|task-0] WorkerSourceTask{id=servicenow-source-0} flushing 0 outstanding messages for offset commit (org.apache.kafka.connect.runtime.WorkerSourceTask:482)
# [2021-08-02 15:16:54,096] ERROR [servicenow-source|task-0] WorkerSourceTask{id=servicenow-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:184)
# org.apache.kafka.connect.errors.ConnectException: Exception encountered while calling ServiceNow
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.getObjects(ServiceNowClientImpl.java:174)
#         at io.confluent.connect.servicenow.ServiceNowSourceTask.fetchRecordFromServiceNow(ServiceNowSourceTask.java:183)
#         at io.confluent.connect.servicenow.ServiceNowSourceTask.poll(ServiceNowSourceTask.java:147)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:268)
#         at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:241)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: java.net.SocketTimeoutException: Read timed out
#         at java.base/java.net.SocketInputStream.socketRead0(Native Method)
#         at java.base/java.net.SocketInputStream.socketRead(SocketInputStream.java:115)
#         at java.base/java.net.SocketInputStream.read(SocketInputStream.java:168)
#         at java.base/java.net.SocketInputStream.read(SocketInputStream.java:140)
#         at java.base/sun.security.ssl.SSLSocketInputRecord.read(SSLSocketInputRecord.java:478)
#         at java.base/sun.security.ssl.SSLSocketInputRecord.readHeader(SSLSocketInputRecord.java:472)
#         at java.base/sun.security.ssl.SSLSocketInputRecord.bytesInCompletePacket(SSLSocketInputRecord.java:70)
#         at java.base/sun.security.ssl.SSLSocketImpl.readApplicationRecord(SSLSocketImpl.java:1364)
#         at java.base/sun.security.ssl.SSLSocketImpl$AppInputStream.read(SSLSocketImpl.java:973)
#         at org.apache.http.impl.io.SessionInputBufferImpl.streamRead(SessionInputBufferImpl.java:137)
#         at org.apache.http.impl.io.SessionInputBufferImpl.fillBuffer(SessionInputBufferImpl.java:153)
#         at org.apache.http.impl.io.SessionInputBufferImpl.readLine(SessionInputBufferImpl.java:280)
#         at org.apache.http.impl.io.ChunkedInputStream.getChunkSize(ChunkedInputStream.java:261)
#         at org.apache.http.impl.io.ChunkedInputStream.nextChunk(ChunkedInputStream.java:222)
#         at org.apache.http.impl.io.ChunkedInputStream.read(ChunkedInputStream.java:183)
#         at org.apache.http.conn.EofSensorInputStream.read(EofSensorInputStream.java:135)
#         at java.base/java.util.zip.InflaterInputStream.fill(InflaterInputStream.java:243)
#         at java.base/java.util.zip.InflaterInputStream.read(InflaterInputStream.java:159)
#         at java.base/java.util.zip.GZIPInputStream.read(GZIPInputStream.java:118)
#         at org.apache.http.client.entity.LazyDecompressingInputStream.read(LazyDecompressingInputStream.java:70)
#         at java.base/java.io.FilterInputStream.read(FilterInputStream.java:133)
#         at com.google.api.client.util.LoggingInputStream.read(LoggingInputStream.java:57)
#         at java.base/java.io.FilterInputStream.read(FilterInputStream.java:107)
#         at com.google.api.client.util.ByteStreams.copy(ByteStreams.java:49)
#         at com.google.api.client.util.IOUtils.copy(IOUtils.java:87)
#         at com.google.api.client.util.IOUtils.copy(IOUtils.java:59)
#         at com.google.api.client.http.HttpResponse.parseAsString(HttpResponse.java:473)
#         at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.getObjects(ServiceNowClientImpl.java:167)
#         ... 11 more




# [2021-08-02 15:42:54,104] ERROR [servicenow-source|task-0] WorkerSourceTask{id=servicenow-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:184)
# io.confluent.connect.utils.retry.RetryCountExceeded: Failed after 4 attempts to send request to ServiceNow: Connect to nginx_proxy:8888 [nginx_proxy/172.19.0.3] failed: connect timed out
# 	at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:429)
# 	at io.confluent.connect.utils.retry.RetryPolicy.call(RetryPolicy.java:337)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.executeRequest(ServiceNowClientImpl.java:229)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.get(ServiceNowClientImpl.java:183)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.getObjects(ServiceNowClientImpl.java:146)
# 	at io.confluent.connect.servicenow.ServiceNowSourceTask.fetchRecordFromServiceNow(ServiceNowSourceTask.java:183)
# 	at io.confluent.connect.servicenow.ServiceNowSourceTask.poll(ServiceNowSourceTask.java:147)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.poll(WorkerSourceTask.java:268)
# 	at org.apache.kafka.connect.runtime.WorkerSourceTask.execute(WorkerSourceTask.java:241)
# 	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:182)
# 	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:231)
# 	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
# 	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
# 	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
# 	at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.http.conn.ConnectTimeoutException: Connect to nginx_proxy:8888 [nginx_proxy/172.19.0.3] failed: connect timed out
# 	at org.apache.http.impl.conn.DefaultHttpClientConnectionOperator.connect(DefaultHttpClientConnectionOperator.java:151)
# 	at org.apache.http.impl.conn.PoolingHttpClientConnectionManager.connect(PoolingHttpClientConnectionManager.java:374)
# 	at org.apache.http.impl.execchain.MainClientExec.establishRoute(MainClientExec.java:401)
# 	at org.apache.http.impl.execchain.MainClientExec.execute(MainClientExec.java:236)
# 	at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:186)
# 	at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:89)
# 	at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:110)
# 	at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:185)
# 	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
# 	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
# 	at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
# 	at com.google.api.client.http.apache.v2.ApacheHttpRequest.execute(ApacheHttpRequest.java:71)
# 	at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:996)
# 	at io.confluent.connect.servicenow.rest.ServiceNowClientImpl.lambda$executeRequest$2(ServiceNowClientImpl.java:230)
# 	at io.confluent.connect.utils.retry.RetryPolicy.lambda$call$1(RetryPolicy.java:337)
# 	at io.confluent.connect.utils.retry.RetryPolicy.callWith(RetryPolicy.java:417)
# 	... 15 more
# Caused by: java.net.SocketTimeoutException: connect timed out
# 	at java.base/java.net.PlainSocketImpl.socketConnect(Native Method)
# 	at java.base/java.net.AbstractPlainSocketImpl.doConnect(AbstractPlainSocketImpl.java:399)
# 	at java.base/java.net.AbstractPlainSocketImpl.connectToAddress(AbstractPlainSocketImpl.java:242)
# 	at java.base/java.net.AbstractPlainSocketImpl.connect(AbstractPlainSocketImpl.java:224)
# 	at java.base/java.net.SocksSocketImpl.connect(SocksSocketImpl.java:392)
# 	at java.base/java.net.Socket.connect(Socket.java:609)
# 	at org.apache.http.conn.socket.PlainConnectionSocketFactory.connectSocket(PlainConnectionSocketFactory.java:75)
# 	at org.apache.http.impl.conn.DefaultHttpClientConnectionOperator.connect(DefaultHttpClientConnectionOperator.java:142)
# 	... 30 more