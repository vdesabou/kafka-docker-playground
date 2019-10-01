#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../scripts/reset-cluster.sh

echo "Sending messages to topic http-messages"
seq 10 | docker container exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

echo "-------------------------------------"
echo "Running Simple (No) Authentication Example"
echo "-------------------------------------"

echo "Creating HttpSinkNoAuth connector"
docker-compose exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
          "name": "HttpSinkNoAuth",
          "config": {
               "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "http.api.url": "http://http-service-no-auth:8080/api/messages"
          }}' \
     http://localhost:8083/connectors | jq .


sleep 10

echo "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq .
