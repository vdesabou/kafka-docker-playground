#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

for component in JsonFieldToKey
do
     set +e
     log "🏗 Building jar for ${component}"
     docker run -i --rm -e KAFKA_CLIENT_TAG=$KAFKA_CLIENT_TAG -e TAG=$TAG_BASE -v "${DIR}/${component}":/usr/src/mymaven -v "$HOME/.m2":/root/.m2 -v "${DIR}/${component}/target:/usr/src/mymaven/target" -w /usr/src/mymaven maven:3.6.1-jdk-11 mvn -Dkafka.tag=$TAG -Dkafka.client.tag=$KAFKA_CLIENT_TAG package > /tmp/result.log 2>&1
     if [ $? != 0 ]
     then
          logerror "ERROR: failed to build java component $component"
          tail -500 /tmp/result.log
          exit 1
     fi
     set -e
done

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.custom-smt-json-array.yml"

log "Creating MQTT Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
               "tasks.max": "1",
               "mqtt.server.uri": "tcp://mosquitto:1883",
               "mqtt.topics":"my-mqtt-topic",
               "kafka.topic":"mqtt-json-array-topic",
               "mqtt.qos": "2",
               "mqtt.username": "myuser",
               "mqtt.password": "mypassword",
               "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
               "transforms" : "JsonFieldToKey",
               "transforms.JsonFieldToKey.type": "com.github.vdesabou.kafka.connect.transforms.JsonFieldToKey",
               "transforms.JsonFieldToKey.field": "$[0][\"sensor\"]",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/source-mqtt-json-array/config | jq .


sleep 5

log "Send message to MQTT in my-mqtt-topic topic"
docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "[{\"timestamp\": 130, \"sensor\": \"MySensorValue\"}, {\"timestamp\": 140, \"sensor\": \"MySensorValue\"}, {\"timestamp\": 150, \"sensor\": \"MySensorValue\"}]"'

sleep 5

log "Verify we have received the json data in mqtt-json-array-topic topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic mqtt-json-array-topic --from-beginning --max-messages 1 --property print.key=true --property key.separator=,

# Results (Key is now "MySensorValue"):

# MySensorValue,[{"timestamp": 130, "sensor": "MySensorValue"}, {"timestamp": 140, "sensor": "MySensorValue"}, {"timestamp": 150, "sensor": "MySensorValue"}]