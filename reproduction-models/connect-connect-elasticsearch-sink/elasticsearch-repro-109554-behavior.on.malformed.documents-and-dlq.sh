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
    export ELASTIC_VERSION="7.12.0"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-109554-behavior.on.malformed.documents-and-dlq.yml"

log "Creating Elasticsearch Sink connector (Elasticsearch version is $ELASTIC_VERSION"
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
               "schema.ignore": "true",
               "connection.url": "http://elasticsearch:9200",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "drop.invalid.message": "true",
               "behavior.on.null.values": "ignore",
               "errors.log.include.messages": "true",
               "errors.tolerance": "none",
               "behavior.on.malformed.documents": "warn",
               "errors.log.enable": "true"
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
               "schema.ignore": "true",
               "connection.url": "http://elasticsearch:9200",
               "type.name": "kafka-connect",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "drop.invalid.message": "true",
               "behavior.on.null.values": "ignore",
               "errors.log.include.messages": "true",
               "errors.tolerance": "none",
               "behavior.on.malformed.documents": "warn",
               "errors.log.enable": "true",
               "transforms": "AddPrefix",
               "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.replacement": "new",
               "transforms.AddPrefix.regex": ".*"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi

log "Sending messages to topic test-elasticsearch-sink"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-elasticsearch-sink << EOF
"{\"customer_name\":\"Ed\", \"complaint_type\":\"Dirty car\", \"trip_cost\": 29.10, \"new_customer\": false, \"number_of_rides\": 22}"
EOF

# [2022-06-15 16:15:54,045] ERROR [elasticsearch-sink|task-0] Failed to execute bulk request due to 'org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes' after 6 attempt(s) (io.confluent.connect.elasticsearch.RetryUtil:164)
# org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes
#         at org.elasticsearch.common.compress.CompressorFactory.compressor(CompressorFactory.java:42)
#         at org.elasticsearch.common.xcontent.XContentHelper.createParser(XContentHelper.java:76)
#         at org.elasticsearch.client.RequestConverters.bulk(RequestConverters.java:226)
#         at org.elasticsearch.client.RestHighLevelClient.internalPerformRequest(RestHighLevelClient.java:2167)
#         at org.elasticsearch.client.RestHighLevelClient.performRequest(RestHighLevelClient.java:2137)
#         at org.elasticsearch.client.RestHighLevelClient.performRequestAndParseEntity(RestHighLevelClient.java:2105)
#         at org.elasticsearch.client.RestHighLevelClient.bulk(RestHighLevelClient.java:620)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$0(ElasticsearchClient.java:171)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:158)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:119)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.callWithRetries(ElasticsearchClient.java:426)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$1(ElasticsearchClient.java:169)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-06-15 16:15:54,047] WARN [elasticsearch-sink|task-0] Bulk request 1 failed (io.confluent.connect.elasticsearch.ElasticsearchClient:397)
# org.apache.kafka.connect.errors.ConnectException: Failed to execute bulk request due to 'org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes' after 6 attempt(s)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:165)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:119)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.callWithRetries(ElasticsearchClient.java:426)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$1(ElasticsearchClient.java:169)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes
#         at org.elasticsearch.common.compress.CompressorFactory.compressor(CompressorFactory.java:42)
#         at org.elasticsearch.common.xcontent.XContentHelper.createParser(XContentHelper.java:76)
#         at org.elasticsearch.client.RequestConverters.bulk(RequestConverters.java:226)
#         at org.elasticsearch.client.RestHighLevelClient.internalPerformRequest(RestHighLevelClient.java:2167)
#         at org.elasticsearch.client.RestHighLevelClient.performRequest(RestHighLevelClient.java:2137)
#         at org.elasticsearch.client.RestHighLevelClient.performRequestAndParseEntity(RestHighLevelClient.java:2105)
#         at org.elasticsearch.client.RestHighLevelClient.bulk(RestHighLevelClient.java:620)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$0(ElasticsearchClient.java:171)
#         at io.conflue

# {
#   "elasticsearch-sink": {
#     "status": {
#       "name": "elasticsearch-sink",
#       "connector": {
#         "state": "RUNNING",
#         "worker_id": "connect:8083"
#       },
#       "tasks": [
#         {
#           "id": 0,
#           "state": "RUNNING",
#           "worker_id": "connect:8083"
#         }
#       ],
#       "type": "sink"
#     },

log "Check DLQ"
timeout 10 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic dlq --from-beginning 

# empty