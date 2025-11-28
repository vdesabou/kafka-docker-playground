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

cd ../../connect/connect-http-source/
if [ ! -f jcl-over-slf4j-2.0.7.jar ]
then
     wget -q https://repo1.maven.org/maven2/org/slf4j/jcl-over-slf4j/2.0.7/jcl-over-slf4j-2.0.7.jar
fi
cd -

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.chaing-offset.no-auth.yml"

playground debug log-level set --package "org.apache.http" --level TRACE

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
    "request.interval.ms": "5000"
}
EOF

log "Wait 5 seconds for connector to start and fetch initial batch"
sleep 5

playground topic consume --topic http-topic-messages --min-expected-messages 3 --timeout 10

log "The connector should fetch new data every 5 seconds"