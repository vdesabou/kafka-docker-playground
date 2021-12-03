#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../ccloud/environment/start.sh "${PWD}/docker-compose.yml"

MQTT_TOPIC="my-mqtt-topic"
KAFKA_TOPIC="mqtt-source-1"

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     create_topic $KAFKA_TOPIC
     set -e
fi

log "Creating MQTT Source connector"
generate_post_data()
{
  cat <<EOF
{
    "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
    "tasks.max": "1",
    "mqtt.server.uri": "tcp://mosquitto:1883",
    "mqtt.topics":"$MQTT_TOPIC",
    "kafka.topic":"$KAFKA_TOPIC",
    "mqtt.qos": "2",
    "mqtt.username": "myuser",
    "mqtt.password": "mypassword",
    "topic.creation.default.replication.factor": "-1",
    "topic.creation.default.partitions": "-1"
   }
EOF
}

curl -X PUT \
     -H "Content-Type: application/json" \
     --data "$(generate_post_data)" \
     http://localhost:8083/connectors/source-mqtt/config | jq .


sleep 5

log "Send message to MQTT in $MQTT_TOPIC topic"
docker exec -e MQTT_TOPIC="$MQTT_TOPIC" mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "$MQTT_TOPIC" -m "sample-msg-1"'

sleep 5

log "Verify we have received the data in $MQTT_TOPIC topic"
printf "bootstrap.servers=$BOOTSTRAP_SERVERS\n" >> ${DIR}/../../ccloud/environment/data
printf "ssl.endpoint.identification.algorithm=https\n" >> ${DIR}/../../ccloud/environment/data
printf "security.protocol=SASL_SSL\n" >> ${DIR}/../../ccloud/environment/data
printf "sasl.mechanism=PLAIN\n" >> ${DIR}/../../ccloud/environment/data
printf "sasl.jaas.config=$SASL_JAAS_CONFIG\n" >> ${DIR}/../../ccloud/environment/data 
 
timeout 60 docker exec -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e KAFKA_TOPIC="$KAFKA_TOPIC" connect bash -c 'kafka-console-consumer --bootstrap-server $BOOTSTRAP_SERVERS  --consumer.config /data/ --topic $KAFKA_TOPIC --from-beginning --max-messages 1'