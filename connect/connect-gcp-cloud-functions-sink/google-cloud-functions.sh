#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
PROJECT=${1:-vincent-de-saboulin-lab}
REGION=${2:-us-central1}
FUNCTION=${3:-function-1}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Produce test data to the functions-messages topic in Kafka"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic functions-messages --property parse.key=true --property key.separator=, << EOF
key1,value1
key2,value2
key3,value3
EOF

log "Creating Google Cloud Functions Sink connector"
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

log "Confirm that the messages were delivered to the result topic in Kafka"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic test-result --from-beginning --max-messages 3
