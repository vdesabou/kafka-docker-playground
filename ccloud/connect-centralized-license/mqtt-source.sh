#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

set +e
playground topic delete --topic _confluent-command
set -e

MQTT_TOPIC=kafka_docker_pg_mqtt$TAG
MQTT_TOPIC=${MQTT_TOPIC//[-.]/}

set +e
playground topic delete --topic $MQTT_TOPIC
set -e


playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.mqtt-source.yml"


#############

log "Creating MQTT Source connector"
playground connector create-or-update --connector mqtt-source  << EOF
{
     "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
     "tasks.max": "1",
     "mqtt.server.uri": "tcp://mosquitto:1883",
     "mqtt.topics":"my-mqtt-topic",
     "kafka.topic": "$MQTT_TOPIC",
     "mqtt.qos": "2",
     "mqtt.username": "myuser",
     "mqtt.password": "mypassword",
     "topic.creation.default.replication.factor": "-1",
     "topic.creation.default.partitions": "-1"
}
EOF

sleep 5

log "Send message to MQTT in my-mqtt-topic topic"
docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "sample-msg-1"'

sleep 10

docker container logs --tail=600 connect

log "Verify we have received the data in $MQTT_TOPIC topic"
playground topic consume --topic $MQTT_TOPIC --min-expected-messages 1 --timeout 60