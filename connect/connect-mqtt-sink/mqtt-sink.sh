#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic sink-messages"
playground topic produce --topic sink-messages --nb-messages 1 << 'EOF'
This is my message
EOF

log "Creating MQTT Sink connector"
playground connector create-or-update --connector sink-mqtt  << EOF
{
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
}
EOF


sleep 5

log "Verify we have received messages in MQTT sink-messages topic"
timeout 60 docker exec mosquitto sh -c 'mosquitto_sub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "sink-messages" -C 1' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "This is my message" /tmp/result.log