#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# As of version 11.0.0, the connector uses the Elasticsearch High Level REST Client (version 7.0.1),
# which means only Elasticsearch 7.x is supported.

export ELASTIC_VERSION="6.8.3"
if version_gt $CONNECTOR_TAG "10.9.9"
then
    log "Connector version is > 11.0.0, using Elasticsearch 7.x"
    export ELASTIC_VERSION="7.10.1" # it doesn't work with 7.12.0
else
     log "This has been untested"
     exit 111
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-mutiple-instances.yml"

logwarn "Pausing container elasticsearch01"
docker container pause elasticsearch01

log "Creating Elasticsearch Sink connector (Elasticsearch version is $ELASTIC_VERSION)"
if version_gt $CONNECTOR_TAG "10.9.9"
then
     # 7.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch01:9200,http://elasticsearch02:9200,http://elasticsearch03:9200"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
else
     # 6.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch01:9200,http://elasticsearch02:9200,http://elasticsearch03:9200"
               "type.name": "kafka-connect"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi


log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9201/test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"


# FIXTHIS
# [2021-05-05 12:33:31,571] ERROR WorkerSinkTask{id=elasticsearch-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
# org.apache.kafka.connect.errors.ConnectException: Exiting WorkerSinkTask due to unrecoverable exception.
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:614)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.poll(WorkerSinkTask.java:329)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.iteration(WorkerSinkTask.java:232)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.execute(WorkerSinkTask.java:201)
#         at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:189)
#         at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:238)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to create index test-elasticsearch-sink.
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.callWithRetries(ElasticsearchClient.java:371)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.createIndex(ElasticsearchClient.java:189)
#         at io.confluent.connect.elasticsearch.ElasticsearchSinkTask.ensureIndexExists(ElasticsearchSinkTask.java:163)
#         at io.confluent.connect.elasticsearch.ElasticsearchSinkTask.put(ElasticsearchSinkTask.java:90)
#         at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:586)
#         ... 10 more
# Caused by: org.apache.kafka.connect.errors.ConnectException: Failed to create index test-elasticsearch-sink
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:164)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:120)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.callWithRetries(ElasticsearchClient.java:364)
#         ... 14 more
# Caused by: java.net.SocketTimeoutException: 3,000 milliseconds timeout on connection http-outgoing-7 [ACTIVE]
#         at org.elasticsearch.client.RestClient.extractAndWrapCause(RestClient.java:789)
#         at org.elasticsearch.client.RestClient.performRequest(RestClient.java:225)
#         at org.elasticsearch.client.RestClient.performRequest(RestClient.java:212)
#         at org.elasticsearch.client.RestHighLevelClient.internalPerformRequest(RestHighLevelClient.java:1433)
#         at org.elasticsearch.client.RestHighLevelClient.performRequest(RestHighLevelClient.java:1418)
#         at org.elasticsearch.client.RestHighLevelClient.performRequestAndParseEntity(RestHighLevelClient.java:1385)
#         at org.elasticsearch.client.IndicesClient.create(IndicesClient.java:125)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$createIndex$2(ElasticsearchClient.java:193)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:161)
#         ... 16 more
# Caused by: java.net.SocketTimeoutException: 3,000 milliseconds timeout on connection http-outgoing-7 [ACTIVE]
#         at org.apache.http.nio.protocol.HttpAsyncRequestExecutor.timeout(HttpAsyncRequestExecutor.java:387)
#         at org.apache.http.impl.nio.client.InternalIODispatch.onTimeout(InternalIODispatch.java:92)
#         at org.apache.http.impl.nio.client.InternalIODispatch.onTimeout(InternalIODispatch.java:39)
#         at org.apache.http.impl.nio.reactor.AbstractIODispatch.timeout(AbstractIODispatch.java:175)
#         at org.apache.http.impl.nio.reactor.BaseIOReactor.sessionTimedOut(BaseIOReactor.java:263)
#         at org.apache.http.impl.nio.reactor.AbstractIOReactor.timeoutCheck(AbstractIOReactor.java:492)
#         at org.apache.http.impl.nio.reactor.BaseIOReactor.validate(BaseIOReactor.java:213)
#         at org.apache.http.impl.nio.reactor.AbstractIOReactor.execute(AbstractIOReactor.java:280)
#         at org.apache.http.impl.nio.reactor.BaseIOReactor.execute(BaseIOReactor.java:104)
#         at org.apache.http.impl.nio.reactor.AbstractMultiworkerIOReactor$Worker.run(AbstractMultiworkerIOReactor.java:591)
#         ... 1 more