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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Elasticsearch Sink connector (Elasticsearch version is $ELASTIC_VERSION")
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
               "transforms": "HoistField",
               "transforms.HoistField.type": "org.apache.kafka.connect.transforms.HoistField$Value",
               "transforms.HoistField.field": "myPayload"
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
               "transforms": "HoistField",
               "transforms.HoistField.type": "org.apache.kafka.connect.transforms.HoistField$Value",
               "transforms.HoistField.field": "myPayload"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi

log "Sending messages to topic test-elasticsearch-sink"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-elasticsearch-sink << EOF
"{\"customer_name\":\"Ed\", \"complaint_type\":\"Dirty car\", \"trip_cost\": 29.10, \"new_customer\": false, \"number_of_rides\": 22}"
EOF

# Without HoistField SMT
# [2022-01-10 11:54:30,234] WARN [elasticsearch-sink|task-0] Bulk request 1 failed (io.confluent.connect.elasticsearch.ElasticsearchClient:396)
# org.apache.kafka.connect.errors.ConnectException: Failed to execute bulk request due to 'org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes' after 6 attempt(s)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:165)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:119)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.callWithRetries(ElasticsearchClient.java:425)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$1(ElasticsearchClient.java:168)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# Caused by: org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes
#         at org.elasticsearch.common.compress.CompressorFactory.compressor(CompressorFactory.java:54)
#         at org.elasticsearch.common.xcontent.XContentHelper.createParser(XContentHelper.java:71)
#         at org.elasticsearch.client.RequestConverters.bulk(RequestConverters.java:234)
#         at org.elasticsearch.client.RestHighLevelClient.internalPerformRequest(RestHighLevelClient.java:1609)
#         at org.elasticsearch.client.RestHighLevelClient.performRequest(RestHighLevelClient.java:1583)
#         at org.elasticsearch.client.RestHighLevelClient.performRequestAndParseEntity(RestHighLevelClient.java:1553)
#         at org.elasticsearch.client.RestHighLevelClient.bulk(RestHighLevelClient.java:533)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$0(ElasticsearchClient.java:170)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:158)
#         ... 8 more


sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Ed" /tmp/result.log | grep "myPayload"

# {
#   "took" : 2,
#   "timed_out" : false,
#   "_shards" : {
#     "total" : 1,
#     "successful" : 1,
#     "skipped" : 0,
#     "failed" : 0
#   },
#   "hits" : {
#     "total" : {
#       "value" : 1,
#       "relation" : "eq"
#     },
#     "max_score" : 1.0,
#     "hits" : [
#       {
#         "_index" : "test-elasticsearch-sink",
#         "_type" : "_doc",
#         "_id" : "test-elasticsearch-sink+0+0",
#         "_score" : 1.0,
#         "_source" : {
#           "myPayload" : "{\"customer_name\":\"Ed\", \"complaint_type\":\"Dirty car\", \"trip_cost\": 29.10, \"new_customer\": false, \"number_of_rides\": 22}"
#         }
#       }
#     ]
#   }
# }
