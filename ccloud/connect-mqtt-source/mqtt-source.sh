#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi
#############

MQTT_TOPIC=kafka_docker_pg_mqtt$TAG
MQTT_TOPIC=${MQTT_TOPIC//[-.]/}

set +e
playground topic delete --topic $MQTT_TOPIC
set -e

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     playground topic create --topic $MQTT_TOPIC
     set -e

     sleep 30
fi

log "Send message to MQTT in my-mqtt-topic topic"
docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "sample-msg-1"'

sleep 5

log "Creating MQTT Source connector"
playground connector create-or-update --connector mqtt-source << EOF
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
               "topic.creation.default.partitions": "-1",
               "confluent.topic.ssl.endpoint.identification.algorithm" : "https",
               "confluent.topic.sasl.mechanism" : "PLAIN",
               "confluent.topic.bootstrap.servers": "\${file:/data:bootstrap.servers}",
               "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
               "confluent.topic.security.protocol" : "SASL_SSL",
               "confluent.topic.replication.factor": "3"
          }
EOF

sleep 5

for((i=0;i<100;i++)); do
     log "Send message again to MQTT in my-mqtt-topic topic"
     docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "sample-msg-1"'
done

sleep 30

log "Verify we have received the data in $MQTT_TOPIC topic"
playground topic consume --topic $MQTT_TOPIC --min-expected-messages 2 --timeout 60