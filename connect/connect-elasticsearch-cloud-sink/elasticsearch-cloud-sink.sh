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

ELASTICSEARCH_CLOUD_ENDPOINT=${ELASTICSEARCH_CLOUD_ENDPOINT:-$1}
ELASTICSEARCH_CLOUD_USERNAME=${ELASTICSEARCH_CLOUD_USERNAME:-$2}
ELASTICSEARCH_CLOUD_PASSWORD=${ELASTICSEARCH_CLOUD_PASSWORD:-$3}

if [ -z "$ELASTICSEARCH_CLOUD_ENDPOINT" ]
then
     logerror "ELASTICSEARCH_CLOUD_ENDPOINT is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$ELASTICSEARCH_CLOUD_USERNAME" ]
then
     logerror "ELASTICSEARCH_CLOUD_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$ELASTICSEARCH_CLOUD_PASSWORD" ]
then
     logerror "ELASTICSEARCH_CLOUD_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Elasticsearch Sink connector"
playground connector create-or-update --connector elasticsearch-cloud-sink  << EOF
{
     "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
     "tasks.max": "1",
     "topics": "test-elasticsearch-sink",
     "key.ignore": "true",
     "connection.url": "$ELASTICSEARCH_CLOUD_ENDPOINT",
     "connection.username": "$ELASTICSEARCH_CLOUD_USERNAME",
     "connection.password": "$ELASTICSEARCH_CLOUD_PASSWORD"
}
EOF

log "Sending messages to topic test-elasticsearch-sink"
playground topic produce -t test-elasticsearch-sink --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

sleep 10

log "Check that the data is available in Elasticsearch Cloud"
curl -u $ELASTICSEARCH_CLOUD_USERNAME:$ELASTICSEARCH_CLOUD_PASSWORD -XGET "$ELASTICSEARCH_CLOUD_ENDPOINT/test-elasticsearch-sink/_search?pretty" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"
