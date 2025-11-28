#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

source ${DIR}/../../scripts/utils.sh

# This example demonstrates chaining offset mode with Elasticsearch's search_after pagination
# The HTTP server returns paginated data with the following Elasticsearch Search API structure:
# {
#   "hits": {
#     "hits": [
#       {
#         "_source": { "@time": 1647948089978, "message": "..." },
#         "sort": [1647948089978]
#       },
#       ...
#     ]
#   }
# }
# The connector makes POST requests to http://httpserver:9006/test-index/_search with body:
# {"size": 100, "sort": [{"@time": "asc"}], "search_after": [<last_sort_value>]}
# and uses the last document's sort value from the response for the next search_after
# 
# Note: If the size parameter isn't set to a value large enough, connector data loss can occur 
# if the number of documents with the same sort parameter value exceeds the size value.

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "0.1.99"
then
     logwarn "minimal supported connector version is 0.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.chaing-offset.no-auth.yml"

log "Creating http-source connector with chaining offset mode (Elasticsearch search_after pagination)"
playground connector create-or-update --connector http-source  << EOF
{
    "tasks.max": "1",
    "connector.class": "io.confluent.connect.http.HttpSourceConnector",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "topic.name.pattern":"http-topic-\${entityName}",
    "entity.names": "messages",
    "url": "http://httpserver:9006/test-index/_search",
    "http.offset.mode": "CHAINING",
    "http.request.method": "POST",
    "http.request.body": "{\\"size\\": 100, \\"sort\\": [{\\"@time\\": \\"asc\\"}], \\"search_after\\": [\${offset}]}",
    "http.initial.offset": "1647948000000",
    "http.response.data.json.pointer": "/hits/hits",
    "http.offset.json.pointer": "/sort/0",
    "http.timer.interval.millis": "5000"
}
EOF

sleep 10

log "Verify we have received the data in http-topic-messages topic (expecting 15 messages across 5 pages)"
playground topic consume --topic http-topic-messages --min-expected-messages 15 --timeout 60

# Expected output: Elasticsearch documents matching the response format
# Example messages:
# Value:{"_index":"test-index","_id":"doc_1647948001000","_score":null,"_source":{"name":"Name1647948001000","time":"1647948001000"},"sort":[1647948001000]}
# Value:{"_index":"test-index","_id":"doc_1647948002000","_score":null,"_source":{"name":"Name1647948002000","time":"1647948002000"},"sort":[1647948002000]}
# Value:{"_index":"test-index","_id":"doc_1647948003000","_score":null,"_source":{"name":"Name1647948003000","time":"1647948003000"},"sort":[1647948003000]}
# 
# Page 1: Documents with timestamps 1647948001000, 1647948002000, 1647948003000
# The connector uses the last sort value [1647948003000] to request page 2 with search_after: [1647948003000]
# Page 2: Documents with timestamps 1647948004000, 1647948005000, 1647948006000
# And so on for 5 pages total (3 documents per page = 15 total documents)


# CreateTime:2025-11-28 16:38:41.954|Partition:0|Offset:0|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948001000","_score":null,"_source":{"name":"Name1647948001000","time":"1647948001000"},"sort":[1647948001000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:41.955|Partition:0|Offset:1|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948002000","_score":null,"_source":{"name":"Name1647948002000","time":"1647948002000"},"sort":[1647948002000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:41.955|Partition:0|Offset:2|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948003000","_score":null,"_source":{"name":"Name1647948003000","time":"1647948003000"},"sort":[1647948003000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.60|Partition:0|Offset:3|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948004000","_score":null,"_source":{"name":"Name1647948004000","time":"1647948004000"},"sort":[1647948004000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.61|Partition:0|Offset:4|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948005000","_score":null,"_source":{"name":"Name1647948005000","time":"1647948005000"},"sort":[1647948005000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.62|Partition:0|Offset:5|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948006000","_score":null,"_source":{"name":"Name1647948006000","time":"1647948006000"},"sort":[1647948006000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.164|Partition:0|Offset:6|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948007000","_score":null,"_source":{"name":"Name1647948007000","time":"1647948007000"},"sort":[1647948007000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.165|Partition:0|Offset:7|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948008000","_score":null,"_source":{"name":"Name1647948008000","time":"1647948008000"},"sort":[1647948008000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.165|Partition:0|Offset:8|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948009000","_score":null,"_source":{"name":"Name1647948009000","time":"1647948009000"},"sort":[1647948009000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.296|Partition:0|Offset:9|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948010000","_score":null,"_source":{"name":"Name1647948010000","time":"1647948010000"},"sort":[1647948010000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.296|Partition:0|Offset:10|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948011000","_score":null,"_source":{"name":"Name1647948011000","time":"1647948011000"},"sort":[1647948011000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.296|Partition:0|Offset:11|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948012000","_score":null,"_source":{"name":"Name1647948012000","time":"1647948012000"},"sort":[1647948012000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.398|Partition:0|Offset:12|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948013000","_score":null,"_source":{"name":"Name1647948013000","time":"1647948013000"},"sort":[1647948013000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.398|Partition:0|Offset:13|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948014000","_score":null,"_source":{"name":"Name1647948014000","time":"1647948014000"},"sort":[1647948014000]}|ValueSchemaId:
# CreateTime:2025-11-28 16:38:42.398|Partition:0|Offset:14|Headers:NO_HEADERS|Key:null|Value:{"_index":"test-index","_id":"doc_1647948015000","_score":null,"_source":{"name":"Name1647948015000","time":"1647948015000"},"sort":[1647948015000]}|ValueSchemaId