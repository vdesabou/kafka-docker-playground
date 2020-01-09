#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF

log "Creating MQTT Sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSinkConnector",
                    "tasks.max": "1",
                    "mqtt.server.uri": "tcp://mosquitto:1883",
                    "topics":"sink-messages",
                    "mqtt.qos": "2",
                    "mqtt.username": "myuser",
                    "mqtt.password": "mypassword",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/sink-mqtt/config | jq .


sleep 5

log "Verify we have received messages in MQTT sink-messages topic"
docker exec mosquitto sh -c 'mosquitto_sub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "sink-messages" -C 1'