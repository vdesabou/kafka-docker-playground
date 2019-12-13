#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Sending messages to topic topic1"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic topic1 --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

echo "Creating AWS DynamoDB Sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.dynamodb.DynamoDbSinkConnector",
                    "tasks.max": "1",
                    "topics": "topic1",
                    "aws.dynamodb.region": "us-east-1",
                    "aws.dynamodb.endpoint": "https://dynamodb.us-east-1.amazonaws.com",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/dynamodb-sink/config | jq .

echo "Sleeping 60 seconds, waiting for table to be created"
sleep 60

echo "Verify data is in DynamoDB"
aws dynamodb scan --table-name topic1 --region us-east-1
