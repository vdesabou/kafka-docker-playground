#!/bin/bash
set -e

# export TAG=6.0.1
# export CONNECTOR_TAG=5.4.3
# export ELASTIC_VERSION="7.12.0"

# [2022-01-10 15:30:08,125] TRACE [elasticsearch-sink3|task-0] Applying transformation org.apache.kafka.connect.transforms.RegexRouter to SinkRecord{kafkaOffset=0, timestampType=CreateTime} ConnectRecord{topic='test-elasticsearch-sink', kafkaPartition=0, key=null, keySchema=Schema{STRING}, value={"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}, valueSchema=null, timestamp=1641828604770, headers=ConnectHeaders(headers=)} (org.apache.kafka.connect.runtime.TransformationChain:47)

# [2022-01-10 15:30:08,283] TRACE [elasticsearch-sink3|task-0] Adding record to queue (io.confluent.connect.elasticsearch.bulk.BulkProcessor:335)
# [2022-01-10 15:30:08,283] DEBUG [elasticsearch-sink3|task-0] Farmer1 Submitting batch of 1 records; 1 unsent and 1 total in-flight records (io.confluent.connect.elasticsearch.bulk.BulkProcessor:189)
# [2022-01-10 15:30:08,285] DEBUG [elasticsearch-sink3|task-0] Farmer1 Processing next batch with 1 outstanding batch requests in flight (io.confluent.connect.elasticsearch.bulk.BulkProcessor:151)
# [2022-01-10 15:30:08,290] TRACE [elasticsearch-sink3|task-0] Thread1 Executing batch 1 of 1 records with attempt 1/6 (io.confluent.connect.elasticsearch.bulk.BulkProcessor:438)
# [2022-01-10 15:30:08,344] DEBUG [elasticsearch-sink3|task-0] Thread1 Bulk request failed; collecting error(s) (io.confluent.connect.elasticsearch.jest.JestElasticsearchClient:549)
# [2022-01-10 15:30:08,347] DEBUG [elasticsearch-sink3|task-0] Thread1 Encountered an illegal document error when executing batch 1 of 1 records. Ignoring and will not index record. Error was [{"type":"mapper_parsing_exception","reason":"failed to parse","caused_by":{"type":"not_x_content_exception","reason":"Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes"}}] (io.confluent.connect.elasticsearch.bulk.BulkProcessor:490)

export TAG=6.0.1
export CONNECTOR_TAG=5.4.3
export ELASTIC_VERSION="6.8.3"

# [2022-01-10 15:33:54,544] TRACE [elasticsearch-sink3|task-0] Applying transformation org.apache.kafka.connect.transforms.RegexRouter to SinkRecord{kafkaOffset=0, timestampType=CreateTime} ConnectRecord{topic='test-elasticsearch-sink', kafkaPartition=0, key=null, keySchema=Schema{STRING}, value={"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}, valueSchema=null, timestamp=1641828831149, headers=ConnectHeaders(headers=)} (org.apache.kafka.connect.runtime.TransformationChain:47)
# [2022-01-10 15:33:54,708] TRACE [elasticsearch-sink3|task-0] Adding record to queue (io.confluent.connect.elasticsearch.bulk.BulkProcessor:335)
# [2022-01-10 15:33:54,709] DEBUG [elasticsearch-sink3|task-0] Farmer1 Submitting batch of 1 records; 1 unsent and 1 total in-flight records (io.confluent.connect.elasticsearch.bulk.BulkProcessor:189)
# [2022-01-10 15:33:54,710] DEBUG [elasticsearch-sink3|task-0] Farmer1 Processing next batch with 1 outstanding batch requests in flight (io.confluent.connect.elasticsearch.bulk.BulkProcessor:151)
# [2022-01-10 15:33:54,713] TRACE [elasticsearch-sink3|task-0] Thread1 Executing batch 1 of 1 records with attempt 1/6 (io.confluent.connect.elasticsearch.bulk.BulkProcessor:438)
# [2022-01-10 15:33:54,757] DEBUG [elasticsearch-sink3|task-0] Thread1 Bulk request failed; collecting error(s) (io.confluent.connect.elasticsearch.jest.JestElasticsearchClient:549)
# [2022-01-10 15:33:54,760] DEBUG [elasticsearch-sink3|task-0] Thread1 Encountered an illegal document error when executing batch 1 of 1 records. Ignoring and will not index record. Error was [{"type":"mapper_parsing_exception","reason":"failed to parse","caused_by":{"type":"not_x_content_exception","reason":"Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes"}}] (io.confluent.connect.elasticsearch.bulk.BulkProcessor:490)
# [2022-01-10 15:34:50,511] DEBUG [elasticsearch-sink3|task-0] Putting 0 records to Elasticsearch (io.confluent.connect.elasticsearch.ElasticsearchSinkTask:125)

# As of version 11.0.0, the connector uses the Elasticsearch High Level REST Client (version 7.0.1),
# which means only Elasticsearch 7.x is supported.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# export ELASTIC_VERSION="6.8.3"
# if version_gt $CONNECTOR_TAG "10.9.9"
# then
#     log "Connector version is > 11.0.0, using Elasticsearch 7.x"
#     export ELASTIC_VERSION="7.12.0"
# fi

# With 11.1.7 we get:

# [2022-01-10 14:46:23,299] ERROR [elasticsearch-sink|task-0] Failed to execute bulk request due to 'org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes' after 6 attempt(s) (io.confluent.connect.elasticsearch.RetryUtil:164)
# org.elasticsearch.common.compress.NotXContentException: Compressor detection can only be called on some xcontent bytes or compressed xcontent bytes
#         at org.elasticsearch.common.compress.CompressorFactory.compressor(CompressorFactory.java:54)
#         at org.elasticsearch.common.xcontent.XContentHelper.createParser(XContentHelper.java:71)
#         at org.elasticsearch.client.RequestConverters.bulk(RequestConverters.java:234)
#         at org.elasticsearch.client.RestHighLevelClient.internalPerformRequest(RestHighLevelClient.java:1609)
#         at org.elasticsearch.client.RestHighLevelClient.performRequest(RestHighLevelClient.java:1583)
#         at org.elasticsearch.client.RestHighLevelClient.performRequestAndParseEntity(RestHighLevelClient.java:1553)
#         at org.elasticsearch.client.RestHighLevelClient.bulk(RestHighLevelClient.java:533)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$0(ElasticsearchClient.java:170)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:158)
#         at io.confluent.connect.elasticsearch.RetryUtil.callWithRetries(RetryUtil.java:119)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.callWithRetries(ElasticsearchClient.java:425)
#         at io.confluent.connect.elasticsearch.ElasticsearchClient.lambda$null$1(ElasticsearchClient.java:168)
#         at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:515)
#         at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:264)
#         at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1128)
#         at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:628)
#         at java.base/java.lang.Thread.run(Thread.java:829)
# [2022-01-10 14:46:23,302] WARN [elasticsearch-sink|task-0] Bulk request 1 failed (io.confluent.connect.elasticsearch.ElasticsearchClient:396)
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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.elasticsearch \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

curl --request PUT \
  --url http://localhost:8083/admin/loggers/org.apache.kafka.connect.runtime.TransformationChain \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data '{
	"level": "TRACE"
}'

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
               "behavior.on.malformed.documents": "ignore",
               "errors.log.enable": "true",
               "transforms": "AddPrefix",
               "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.replacement": "new",
               "transforms.AddPrefix.regex": ".*"
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
               "behavior.on.malformed.documents": "ignore",
               "errors.log.enable": "true",
               "transforms": "AddPrefix",
               "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.replacement": "new",
               "transforms.AddPrefix.regex": ".*"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink3/config | jq .
fi

log "Sending messages to topic test-elasticsearch-sink"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-elasticsearch-sink << EOF
"{\"customer_name\":\"Ed\", \"complaint_type\":\"Dirty car\", \"trip_cost\": 29.10, \"new_customer\": false, \"number_of_rides\": 22}"
EOF

sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/new/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log

