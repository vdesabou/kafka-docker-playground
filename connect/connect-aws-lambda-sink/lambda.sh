#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mSending messages to topic add-topic\033[0m"
seq -f "{\"a\": %g,\"b\": 1}" 10 | docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic add-topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"a","type":"int"},{"name":"b","type":"int"}]}'

echo -e "\033[0;33mCreating AWS Lambda Sink connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
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
          }' \
     http://localhost:8083/connectors/aws-lambda/config | jq .


sleep 10

echo -e "\033[0;33mVerifying topic add-topic-response\033[0m"
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic add-topic-response --from-beginning --max-messages 10
