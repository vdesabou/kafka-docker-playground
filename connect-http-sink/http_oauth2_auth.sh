#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

echo "-------------------------------------"
echo "Running OAuth2 Authentication Example"
echo "-------------------------------------"

echo "Creating HttpSinkOAuth2 connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
          "name": "HttpSinkOAuth2",
          "config": {
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
          }}' \
     http://localhost:8083/connectors | jq .


sleep 10

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X POST \
  http://localhost:10080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq -r '.access_token')


echo "Confirm that the data was sent to the HTTP endpoint."
curl -X GET \
    http://localhost:10080/api/messages \
    -H "Authorization: Bearer ${token}" | jq .
