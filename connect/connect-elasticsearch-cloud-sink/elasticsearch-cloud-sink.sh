#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

# As of version 11.0.0, the connector uses the Elasticsearch High Level REST Client (version 7.0.1),
# which means only Elasticsearch 7.x is supported.

export ELASTIC_VERSION="6.8.3"
if version_gt $CONNECTOR_TAG "10.9.9"
then
    log "Connector version is > 11.0.0, using Elasticsearch 7.x"
    export ELASTIC_VERSION="7.12.0"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

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
               "connection.url": "$ELASTICSEARCH_CLOUD_ENDPOINT",
               "connection.username": "$ELASTICSEARCH_CLOUD_USERNAME",
               "connection.password": "$ELASTICSEARCH_CLOUD_PASSWORD"
               }' \
          http://localhost:8083/connectors/elasticsearch-cloud-sink/config | jq .
else
     # 6.x
     curl -X PUT \
          -H "Content-Type: application/json" \
          --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "$ELASTICSEARCH_CLOUD_ENDPOINT",
               "connection.username": "$ELASTICSEARCH_CLOUD_USERNAME",
               "connection.password": "$ELASTICSEARCH_CLOUD_PASSWORD",
               "type.name": "kafka-connect"
               }' \
          http://localhost:8083/connectors/elasticsearch-cloud-sink/config | jq .
fi


log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Check that the data is available in Elasticsearch Cloud"
curl -u $ELASTICSEARCH_CLOUD_USERNAME:$ELASTICSEARCH_CLOUD_PASSWORD -XGET "$ELASTICSEARCH_CLOUD_ENDPOINT/test-elasticsearch-sink/_search?pretty" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"
