#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic http-messages"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

log "-------------------------------------"
log "Running Simple (No) Authentication Example"
log "-------------------------------------"

log "Creating http-sink connector"
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
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "batch.max.size": "10"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log
grep "10" /tmp/result.log

log "Check the success-responses topic"
playground topic consume --topic success-responses --min-expected-messages 10
# input_record_offset:0,input_record_timestamp:1645173514858,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:1,input_record_timestamp:1645173514881,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:2,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:3,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:4,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:5,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:6,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:7,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:8,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# input_record_offset:9,input_record_timestamp:1645173514882,input_record_partition:0,input_record_topic:http-messages    "{\"id\":1,\"message\":\"1,2,3,4,5,6,7,8,9,10\"}"
# Processed a total of 10 messages