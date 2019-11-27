#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Sending messages to topic add-topic"
seq -f "{\"a\": %g,\"b\": 1}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic add-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"a","type":"int"},{"name":"b","type":"int"}]}'

echo "Creating AWS Lambda Sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "aws-lambda",
               "config": {
                    "connector.class" : "io.confluent.connect.aws.lambda.AwsLambdaSinkConnector",
                    "tasks.max": "1",
                    "topics" : "add-topic",
                    "aws.lambda.function.name" : "Add",
                    "aws.lambda.invocation.type" : "sync",
                    "aws.lambda.batch.size" : "50",
                    "behavior.on.error" : "fail",
                    "aws.lambda.response.topic": "add-topic-response",
                    "aws.lambda.response.bootstrap.servers": "broker:9092",
                    "aws.lambda.response.client.id": "add-topic-response-client",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .


sleep 10

echo "Verifying topic add-topic-response"
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic add-topic-response --from-beginning --max-messages 10
