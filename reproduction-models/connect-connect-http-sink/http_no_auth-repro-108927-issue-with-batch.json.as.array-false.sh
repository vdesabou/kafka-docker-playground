#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-108927-issue-with-batch.json.as.array-false.yml"


log "Sending messages to topic http-messages"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic http-messages --property key.serializer=org.apache.kafka.common.serialization.StringSerializer --property value.schema='{"type":"record","name":"myrecordvalue","fields":[{"name":"ID","type":"long"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}'  --property parse.key=true --property key.separator="|" << EOF
111|{"ID": 111,"product": "foo", "quantity": 100, "price": 50}
222|{"ID": 222,"product": "bar", "quantity": 100, "price": 50}
EOF


log "Creating http-sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "http.api.url": "http://http-service-no-auth:8080/api/messages",
               "batch.json.as.array": "false",
               "batch.max.size": "1",
               "request.body.format": "json",
               "headers": "Content-Type:application/json"
          }' \
     http://localhost:8083/connectors/http-sink/config | jq .


sleep 10

log "Confirm that the data was sent to the HTTP endpoint."
curl localhost:8080/api/messages | jq . > /tmp/result.log  2>&1
cat /tmp/result.log


log "Check the success-responses topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic success-responses --from-beginning --max-messages 2 --property print.headers=true
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


docker logs http-service-no-auth | grep "MESSAGE RECEIVED"

# 2022-06-21 08:59:40.754  INFO 1 --- [nio-8080-exec-1] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: {"ID":111,"product":"foo","quantity":100,"price":50.0}
# 2022-06-21 08:59:40.963  INFO 1 --- [nio-8080-exec-2] i.c.c.http.controller.MessageController  : MESSAGE RECEIVED: {"ID":222,"product":"bar","quantity":100,"price":50.0}