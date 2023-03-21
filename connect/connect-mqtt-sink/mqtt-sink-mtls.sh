#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp vdesabou/kafka-docker-playground-connect:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/ && chmod a+r /tmp/*"
cd ${DIR}

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.mtls.yml"

log "Sending messages to topic sink-messages"
docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages << EOF
This is my message
EOF

log "Creating MQTT Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.mqtt.MqttSinkConnector",
               "tasks.max": "1",
               "mqtt.server.uri": "ssl://mosquitto:8883",
               "topics":"sink-messages",
               "mqtt.qos": "2",
               "mqtt.username": "myuser",
               "mqtt.password": "mypassword",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "mqtt.ssl.trust.store.path": "/tmp/truststore.jks",
               "mqtt.ssl.trust.store.password": "confluent",
               "mqtt.ssl.key.store.path": "/tmp/keystore.jks",
               "mqtt.ssl.key.store.password": "confluent",
               "mqtt.ssl.key.password": "confluent"
          }' \
     http://localhost:8083/connectors/sink-mqtt-mtls/config | jq .


sleep 5

log "Verify we have received messages in MQTT sink-messages topic"
timeout 60 docker exec mosquitto sh -c 'mosquitto_sub -h localhost -p 8883 -u "myuser" -P "mypassword" -t "sink-messages" -C 1 --cafile /tmp/ca.crt --key /tmp/server.key --cert /tmp/server.crt' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "This is my message" /tmp/result.log