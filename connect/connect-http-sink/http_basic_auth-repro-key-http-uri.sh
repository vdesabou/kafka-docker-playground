#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic http-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages --property parse.key=true --property key.separator=, << EOF
messages,value1
messages,value2
messages,value3
EOF


log "-------------------------------------"
log "Running Basic Authentication Example"
log "-------------------------------------"

log "Creating HttpSinkBasicAuth connector"
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
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-basic-auth:8080/api/${key}",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password"
          }' \
     http://localhost:8083/connectors/HttpSinkBasicAuth/config | jq .


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl admin:password@localhost:9083/api/messages | jq .
