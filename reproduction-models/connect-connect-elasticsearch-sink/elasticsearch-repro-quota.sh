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

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-quota.yml"

log "Applying quota for client id my-es-connector"
docker exec broker kafka-configs --bootstrap-server localhost:9092 --alter --add-config 'consumer_byte_rate=1000' --entity-type clients --entity-name my-es-connector

log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"value%g\"}" 1000 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

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
               "connection.url": "http://elasticsearch:9200",
               "consumer.override.client.id": "my-es-connector"
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
               "type.name": "kafka-connect",
               "consumer.override.client.id": "my-es-connector"
               }' \
          http://localhost:8083/connectors/elasticsearch-sink/config | jq .
fi

sleep 10

log "Check throttle happened"
docker exec -i connect bash << EOFCONNECT
wget https://github.com/jiaqi/jmxterm/releases/download/v1.0.2/jmxterm-1.0.2-uber.jar
java -jar jmxterm-1.0.2-uber.jar --url localhost:10002 << EOF
bean kafka.consumer:client-id=my-es-connector,type=consumer-fetch-manager-metrics
info
get fetch-throttle-time-avg
get fetch-throttle-time-max
exit
EOF
EOFCONNECT

log "Check that the data is available in Elasticsearch (this can probably fail)"
curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"


