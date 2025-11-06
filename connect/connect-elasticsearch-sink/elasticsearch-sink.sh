#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "14.0.99"
then
     logwarn "minimal supported connector version is 14.1.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic test-elasticsearch-sink"
playground topic produce -t test-elasticsearch-sink --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

log "Creating Elasticsearch Sink connector"
playground connector create-or-update --connector elasticsearch-sink  << EOF
{
     "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
     "tasks.max": "1",
     "topics": "test-elasticsearch-sink",
     "key.ignore": "true",
     "connection.url": "http://elasticsearch:9200"
}
EOF

sleep 10

log "Check that the data is available in Elasticsearch"
curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"