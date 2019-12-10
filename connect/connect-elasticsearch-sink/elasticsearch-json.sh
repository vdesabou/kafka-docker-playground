#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Creating Elasticsearch Sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
        "name": "elasticsearch-sink",
        "config": {
          "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
          "tasks.max": "1",
          "topics": "test-elasticsearch-sink",
          "connection.url": "http://elasticsearch:9200",
          "type.name": "kafka-connect",
          "value.converter": "org.apache.kafka.connect.json.JsonConverter",
          "key.converter": "org.apache.kafka.connect.json.JsonConverter",
          "key.ignore": "true",
          "schema.ignore":"true",
          "key.converter.schemas.enable": "false",
          "value.converter.schemas.enable": "false"
          }}' \
     http://localhost:8083/connectors | jq .


docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-elasticsearch-sink << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF

sleep 10

echo "Check that the data is available in Elasticsearch"

curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty'


