#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

log "-------------------------------------"
log "Running OAuth2 Authentication Example"
log "-------------------------------------"

log "Creating http-sink connector"
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
     http://localhost:8083/connectors/http-sink/config | jq_docker_cli .


sleep 10

# create token, see https://github.com/confluentinc/kafka-connect-http-demo#oauth2
token=$(curl -X PUT \
  http://localhost:10080/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Authorization: Basic a2MtY2xpZW50OmtjLXNlY3JldA==' \
  -d 'grant_type=client_credentials&scope=any' | jq_docker_cli -r '.access_token')


log "Confirm that the data was sent to the HTTP endpoint."
curl -X GET \
    http://localhost:10080/api/messages \
    -H "Authorization: Bearer ${token}" | jq_docker_cli .
