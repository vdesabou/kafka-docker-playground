#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$CONNECTOR_ZIP" ]
then
     logerror "CONNECTOR_ZIP must be set with a modified version of the connector which supports http proxy"
     logerror "zazkia proxy should be used"

     logerror "see https://stackoverflow.com/a/68265085/2381999"
     logerror "  public static class BigQueryBuilder extends GcpClientBuilder<BigQuery> {"
     logerror "    @Override"
     logerror "    protected BigQuery doBuild(String project, GoogleCredentials credentials) {"
     logerror ""
     logerror "          HttpHost proxy = new HttpHost("zazkia", 49998);"
     logerror "          DefaultHttpClient httpClient = new DefaultHttpClient();"
     logerror ""
     logerror "          httpClient.getParams().setParameter(ConnRoutePNames.DEFAULT_PROXY, proxy);"
     logerror ""
     logerror "          ApacheHttpTransport mHttpTransport = new ApacheHttpTransport(httpClient);"
     logerror ""
     logerror "               HttpTransportFactory hf = new HttpTransportFactory(){"
     logerror "                         @Override"
     logerror "                         public HttpTransport create() {"
     logerror "                              return mHttpTransport;"
     logerror "                         }"
     logerror "                    };"
     logerror ""
     logerror "          TransportOptions options = HttpTransportOptions.newBuilder().setHttpTransportFactory(hf).build();"
     logerror ""
     logerror "          BigQueryOptions.Builder builder = BigQueryOptions.newBuilder()"
     logerror "               .setTransportOptions(options)"
     logerror "               .setProjectId(project);"
     exit 1
fi
# WARNING: must be used with a connector build with this code (to activate proxy support):
# https://stackoverflow.com/a/68265085/2381999
#   public static class BigQueryBuilder extends GcpClientBuilder<BigQuery> {
#     @Override
#     protected BigQuery doBuild(String project, GoogleCredentials credentials) {

#           //HttpHost proxy = new HttpHost("nginx-proxy",8888);
#           HttpHost proxy = new HttpHost("zazkia", 49998);
#           DefaultHttpClient httpClient = new DefaultHttpClient();

#           httpClient.getParams().setParameter(ConnRoutePNames.DEFAULT_PROXY, proxy);

#           ApacheHttpTransport mHttpTransport = new ApacheHttpTransport(httpClient);

#                HttpTransportFactory hf = new HttpTransportFactory(){
#                          @Override
#                          public HttpTransport create() {
#                               return mHttpTransport;
#                          }
#                     };

#           TransportOptions options = HttpTransportOptions.newBuilder().setHttpTransportFactory(hf).build();

#           BigQueryOptions.Builder builder = BigQueryOptions.newBuilder()
#                .setTransportOptions(options)
#                .setProjectId(project);

PROJECT=${1:-vincent-de-saboulin-lab}

KEYFILE="${DIR}/keyfile.json"
if [ ! -f ${KEYFILE} ]
then
     logerror "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

DATASET=pg${USER}ds${GITHUB_RUN_NUMBER}${TAG}
DATASET=${DATASET//[-._]/}

log "Doing gsutil authentication"
set +e
docker rm -f gcloud-config
set -e
docker run -i -v ${KEYFILE}:/tmp/keyfile.json --name gcloud-config google/cloud-sdk:latest gcloud auth activate-service-account --project ${PROJECT} --key-file /tmp/keyfile.json

set +e
log "Drop dataset $DATASET, this might fail"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" rm -r -f -d "$DATASET"
set -e

log "Create dataset $PROJECT.$DATASET"
docker run -i --volumes-from gcloud-config google/cloud-sdk:latest bq --project_id "$PROJECT" mk --dataset --description "used by playground" "$DATASET"


${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-96554-read-timeout-bigqueryexception.yml"

# curl --request PUT \
#   --url http://localhost:8083/admin/loggers/com.wepay.kafka.connect.bigquery \
#   --header 'Accept: application/json' \
#   --header 'Content-Type: application/json' \
#   --data '{
# 	"level": "TRACE"
# }'


log "Creating GCP BigQuery Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "com.wepay.kafka.connect.bigquery.BigQuerySinkConnector",
               "tasks.max" : "1",
               "topics" : "mytopic",
               "sanitizeTopics" : "true",
               "autoCreateTables" : "true",
               "defaultDataset" : "'"$DATASET"'",
               "mergeIntervalMs": "5001",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "bufferSize": "100000",
               "maxWriteSize": "10000",
               "tableWriteWait": "1000",
               "project" : "'"$PROJECT"'",
               "keyfile" : "/tmp/keyfile.json"
          }' \
     http://localhost:8083/connectors/gcp-bigquery-sink/config | jq .

log "Sending a message"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic mytopic --property parse.key=true --property key.separator=, << EOF
1,{"payload":{"price":25,"product":"foo1","id":100,"quantity":100},"schema":{"fields":[{"optional":false,"type":"int32","field":"id"},{"optional":false,"type":"string","field":"product"},{"optional":false,"type":"int32","field":"quantity"},{"optional":false,"type":"int32","field":"price"}],"type":"struct","name":"orders","optional":false}}
EOF

wait_for_log "BigQueryException: Read timed out"

# after 20 seconds, we get

# [2022-03-16 11:40:19,467] ERROR [gcp-bigquery-sink|task-0] WorkerSinkTask{id=gcp-bigquery-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:638)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:334)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:235)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:204)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:199)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:254)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: com.google.cloud.bigquery.BigQueryException: Read timed out
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.translate(HttpBigQueryRpc.java:113)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.getTable(HttpBigQueryRpc.java:285)
#         at com.google.cloud.bigquery.BigQueryImpl$17.call(BigQueryImpl.java:678)
#         at com.google.cloud.bigquery.BigQueryImpl$17.call(BigQueryImpl.java:675)
#         at com.google.api.gax.retrying.DirectRetryingExecutor.submit(DirectRetryingExecutor.java:105)
#         at com.google.cloud.RetryHelper.run(RetryHelper.java:76)
#         at com.google.cloud.RetryHelper.runWithRetries(RetryHelper.java:50)
#         at com.google.cloud.bigquery.BigQueryImpl.getTable(BigQueryImpl.java:674)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.lambda$retrieveCachedTable$2(BigQuerySinkTask.java:338)
#         at java.base/java.util.HashMap.computeIfAbsent(HashMap.java:1134)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.retrieveCachedTable(BigQuerySinkTask.java:338)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.getRecordTable(BigQuerySinkTask.java:210)
#         at com.wepay.kafka.connect.bigquery.BigQuerySinkTask.put(BigQuerySinkTask.java:245)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:604)
#         ... 10 more
# Caused by: java.net.SocketTimeoutException: Read timed out
#         at java.base/java.net.SocketInputStream.socketRead0(Native Method)
#         at java.base/java.net.SocketInputStream.socketRead(SocketInputStream.java:115)
#         at java.base/java.net.SocketInputStream.read(SocketInputStream.java:168)
#         at java.base/java.net.SocketInputStream.read(SocketInputStream.java:140)
#         at org.apache.http.impl.io.AbstractSessionInputBuffer.fillBuffer(AbstractSessionInputBuffer.java:161)
#         at org.apache.http.impl.io.SocketInputBuffer.fillBuffer(SocketInputBuffer.java:82)
#         at org.apache.http.impl.io.AbstractSessionInputBuffer.readLine(AbstractSessionInputBuffer.java:276)
#         at org.apache.http.impl.conn.DefaultHttpResponseParser.parseHead(DefaultHttpResponseParser.java:138)
#         at org.apache.http.impl.conn.DefaultHttpResponseParser.parseHead(DefaultHttpResponseParser.java:56)
#         at org.apache.http.impl.io.AbstractMessageParser.parse(AbstractMessageParser.java:259)
#         at org.apache.http.impl.AbstractHttpClientConnection.receiveResponseHeader(AbstractHttpClientConnection.java:294)
#         at org.apache.http.impl.conn.DefaultClientConnection.receiveResponseHeader(DefaultClientConnection.java:257)
#         at org.apache.http.impl.conn.ManagedClientConnectionImpl.receiveResponseHeader(ManagedClientConnectionImpl.java:207)
#         at org.apache.http.protocol.HttpRequestExecutor.doReceiveResponse(HttpRequestExecutor.java:273)
#         at org.apache.http.protocol.HttpRequestExecutor.execute(HttpRequestExecutor.java:125)
#         at org.apache.http.impl.client.DefaultRequestDirector.createTunnelToTarget(DefaultRequestDirector.java:871)
#         at org.apache.http.impl.client.DefaultRequestDirector.establishRoute(DefaultRequestDirector.java:789)
#         at org.apache.http.impl.client.DefaultRequestDirector.tryConnect(DefaultRequestDirector.java:609)
#         at org.apache.http.impl.client.DefaultRequestDirector.execute(DefaultRequestDirector.java:440)
#         at org.apache.http.impl.client.AbstractHttpClient.doExecute(AbstractHttpClient.java:835)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:83)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:108)
#         at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:56)
#         at com.google.api.client.http.apache.ApacheHttpRequest.execute(ApacheHttpRequest.java:67)
#         at com.google.api.client.http.HttpRequest.execute(HttpRequest.java:1012)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.executeUnparsed(AbstractGoogleClientRequest.java:541)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.executeUnparsed(AbstractGoogleClientRequest.java:474)
#         at com.google.api.client.googleapis.services.AbstractGoogleClientRequest.execute(AbstractGoogleClientRequest.java:591)
#         at com.google.cloud.bigquery.spi.v2.HttpBigQueryRpc.getTable(HttpBigQueryRpc.java:283)
#         ... 22 more