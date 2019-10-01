#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../scripts/reset-cluster.sh

echo "Creating Elasticsearch Sink connector"
docker-compose exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "elasticsearch-sink",
        "config": {
          "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
          "tasks.max": "1",
          "topics": "test-elasticsearch-sink",
          "key.ignore": "true",
          "connection.url": "http://elasticsearch:9200",
          "type.name": "kafka-connect",
          "name": "elasticsearch-sink"
          }}' \
     http://localhost:8083/connectors | jq .


echo "Sending messages to topic test-elasticsearch-sink"
seq -f "{\"f1\": \"value%g\"}" 10 | docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic test-elasticsearch-sink --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

echo "Check that the data is available in Elasticsearch"

curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty'


