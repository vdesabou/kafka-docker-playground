#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.avro.yml"

log "Creating MQTT Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
               "tasks.max": "1",
               "mqtt.server.uri": "tcp://mosquitto:1883",
               "mqtt.topics":"my-mqtt-topic",
               "kafka.topic":"mqtt-avro-topic",
               "mqtt.qos": "2",
               "mqtt.username": "myuser",
               "mqtt.password": "mypassword",
               "transforms" : "fromJson",
               "transforms.fromJson.type" : "com.github.jcustenborder.kafka.connect.json.FromJson$Value",
               "transforms.fromJson.json.schema.location" : "Inline",
               "transforms.fromJson.json.schema.inline" : "{\n  \"$id\": \"https://example.com/person.schema.json\",\n  \"$schema\": \"http://json-schema.org/draft-07/schema#\",\n  \"title\": \"Person\",\n  \"type\": \"object\",\n  \"properties\": {\n    \"firstName\": {\n      \"type\": \"string\",\n      \"description\": \"The person first name.\"\n    },\n    \"lastName\": {\n      \"type\": \"string\",\n      \"description\": \"The person last name.\"\n    },\n    \"age\": {\n      \"description\": \"Age in years which must be equal to or greater than zero.\",\n      \"type\": \"integer\",\n      \"minimum\": 0\n    }\n  }\n}",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/source-mqtt-avro/config | jq .


sleep 5

log "Send message to MQTT in my-mqtt-topic topic"
docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "{\"lastName\":\"Doe\",\"age\":21,\"firstName\":\"John\"}"'

sleep 5

log "Verify we have received the avro data in mqtt-avro-topic topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic mqtt-avro-topic --from-beginning --max-messages 1