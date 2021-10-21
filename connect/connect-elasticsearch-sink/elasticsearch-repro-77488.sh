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

curl --request PUT \
  --url http://localhost:8083/admin/loggers/io.confluent.connect.elasticsearch \
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
               "connection.url": "http://elasticsearch:9200",
               "transforms" : "AddPrefix",
               "transforms.AddPrefix.type" : "org.apache.kafka.connect.transforms.RegexRouter",
               "transforms.AddPrefix.regex" : ".*",
               "transforms.AddPrefix.replacement" : "copy_of_$0"
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
               "connection.url": "http://elasticsearch:9200",
               "type.name": "kafka-connect"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi


log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"value_before_restart%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Check that the new data is available in Elasticsearch, there should be 10 value_before_restart"
curl -XGET 'http://localhost:9200/copy_of_test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
grep -c "value_before_restart" /tmp/result.log

log "Now restart connect worker"
docker restart connect

log "sleep 60"
sleep 60

log "Waiting for repro: Ignoring invalid task provided offset"
docker container logs connect >  connect.log 2>&1
grep "Ignoring invalid task provided offset" connect.log

log "Waiting for repro: Found no committed offset for partition test-elasticsearch-sink-0 should appear twice"
grep "Found no committed offset for partition test-elasticsearch-sink-0" connect.log

log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"value_after_restart%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 80

log "Check that the new data is available in Elasticsearch, there should be 10 value_after_restart"
curl -XGET 'http://localhost:9200/copy_of_test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep -c "value_after_restart" /tmp/result.log
