#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "14.0.99"
then
     logwarn "minimal supported connector version is 14.1.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/8.0/connect/supported-connector-version.html#"
     exit 111
fi

# connector 16.0.0+ uses the Elasticsearch Java API Client and supports Elasticsearch 8.x and 9.x (7.x is no longer supported)
# connector < 16.0.0 uses the High Level REST Client 7.17 and supports Elasticsearch 7.x and 8.x (compatibility mode)
# CONNECTOR_TAG is not set with --connector-zip/--connector-jar, get the version from the artifact name in that case
connector_version="$CONNECTOR_TAG"
if [ -z "$connector_version" ] && [ ! -z "${CONNECTOR_ZIP}${CONNECTOR_JAR}" ]
then
     connector_version=$(basename "${CONNECTOR_ZIP:-$CONNECTOR_JAR}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

if [ -z "$ELASTIC_VERSION" ]
then
     if [ -z "$connector_version" ] || version_gt $connector_version "15.99.99"
     then
          export ELASTIC_VERSION="9.3.0"
     else
          export ELASTIC_VERSION="8.18.2"
     fi
fi
log "Connector version is ${connector_version:-unknown}, using Elasticsearch $ELASTIC_VERSION (set ELASTIC_VERSION to override)"

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