#!/bin/bash
set -e

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "mosquitto_sub"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Creating MQTT Source connector"
docker container exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "source-mqtt",
               "config": {
                    "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
                    "tasks.max": "1",
                    "mqtt.server.uri": "tcp://mosquitto:1883",
                    "mqtt.topics":"my-mqtt-topic",
                    "kafka.topic":"mqtt-source-1",
                    "mqtt.qos": "2",
                    "mqtt.username": "myuser",
                    "mqtt.password": "mypassword",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

echo "Send message to MQTT in mqtt-source-1 topic"
mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "sample-msg-1"

sleep 5

echo "Verify we have received the data in mqtt-source-1 topic"
docker container exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic mqtt-source-1 --from-beginning --max-messages 1