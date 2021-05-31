#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-quota.yml"

log "Applying quota for client id my-es-connector"
docker exec broker kafka-configs --bootstrap-server localhost:9092 --alter --add-config 'consumer_byte_rate=1' --entity-type clients --entity-name my-es-connector

log "Creating Elasticsearch Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
               "tasks.max": "1",
               "topics": "test-elasticsearch-sink",
               "key.ignore": "true",
               "connection.url": "http://elasticsearch:9200",
               "type.name": "kafka-connect",
               "name": "elasticsearch-sink",
               "consumer.override.client.id": "my-es-connector"
          }' \
     http://localhost:8083/connectors/elasticsearch-sink/config | jq .


log "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"value%g\"}" 100 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Check that the data is available in Elasticsearch"

curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty'


