#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mSending messages to topic http-messages\033[0m"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

echo -e "\033[0;33m-------------------------------------\033[0m"
echo -e "\033[0;33mRunning OAuth2 Authentication Example\033[0m"
echo -e "\033[0;33m-------------------------------------\033[0m"

echo -e "\033[0;33mCreating http-sink connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "http.api.url": "http://http-service-oauth2-auth:8080/api/messages",
               "auth.type": "OAUTH2",
               "oauth2.token.url": "http://http-service-oauth2-auth:8080/oauth/token",
               "oauth2.client.id": "kc-client",
               "oauth2.client.secret": "kc-secret"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X PUT \
  http://localhost:10080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


echo -e "\033[0;33mConfirm that the data was sent to the HTTP endpoint.\033[0m"
curl -X GET \
    http://localhost:10080/api/messages \
    -H "Authorization: Bearer ${token}" | jq .
