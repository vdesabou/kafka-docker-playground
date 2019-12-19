#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
PROJECT=${1:-vincent-de-saboulin-lab}
REGION=${2:-us-central1}
FUNCTION=${3:-function-1}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mProduce test data to the functions-messages topic in Kafka\033[0m"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic functions-messages --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF

echo -e "\033[0;33mCreating Google Cloud Functions Sink connector\033[0m"
docker exec -e PROJECT="$PROJECT" -e REGION="$REGION" -e FUNCTION="$FUNCTION" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.gcp.functions.GoogleCloudFunctionsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "functions-messages",
                    "key.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "value.converter":"org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor":1,
                    "function.name": "'"$FUNCTION"'",
                    "project.id": "'"$PROJECT"'",
                    "region": "'"$REGION"'",
                    "reporter.bootstrap.servers": "broker:9092",
                    "reporter.error.topic.name": "test-error",
                    "reporter.error.topic.replication.factor": 1,
                    "reporter.error.topic.key.format": "string",
                    "reporter.error.topic.value.format": "string",
                    "reporter.result.topic.name": "test-result",
                    "reporter.result.topic.key.format": "string",
                    "reporter.result.topic.value.format": "string",
                    "reporter.result.topic.replication.factor": 1
          }' \
     http://localhost:8083/connectors/gcp-functions/config | jq .

sleep 10

echo -e "\033[0;33mConfirm that the messages were delivered to the result topic in Kafka\033[0m"
docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-result --from-beginning --max-messages 3
