#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mCreating Elasticsearch Sink connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/elasticsearch-sink/config | jq .


docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic test-elasticsearch-sink << EOF
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF

sleep 10

echo -e "\033[0;33mCheck that the data is available in Elasticsearch\033[0m"

curl -XGET 'http://localhost:9200/test-elasticsearch-sink/_search?pretty'


