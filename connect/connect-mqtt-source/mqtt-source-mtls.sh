#!/bin/bash
set -e


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

cd ${DIR}/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/ && chmod a+r /tmp/*"
cd ${DIR}

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.mtls.yml"

log "Creating MQTT Source connector"
playground connector create-or-update --connector source-mqtt << EOF
{
     "connector.class": "io.confluent.connect.mqtt.MqttSourceConnector",
     "tasks.max": "1",
     "mqtt.server.uri": "ssl://mosquitto:8883",
     "mqtt.topics":"my-mqtt-topic",
     "kafka.topic":"mqtt-source-1",
     "mqtt.qos": "2",
     "mqtt.username": "myuser",
     "mqtt.password": "mypassword",
     "confluent.license": "",
     "confluent.topic.bootstrap.servers": "broker:9092",
     "confluent.topic.replication.factor": "1",
     "mqtt.ssl.trust.store.path": "/tmp/truststore.jks",
     "mqtt.ssl.trust.store.password": "confluent",
     "mqtt.ssl.key.store.path": "/tmp/keystore.jks",
     "mqtt.ssl.key.store.password": "confluent",
     "mqtt.ssl.key.password": "confluent"
}
EOF


sleep 5

log "Send message to MQTT in my-mqtt-topic topic"
docker exec mosquitto sh -c 'mosquitto_pub -h localhost -p 8883 -u "myuser" -P "mypassword" -t "my-mqtt-topic" -m "sample-msg-1" --cafile /tmp/ca.crt --key /tmp/server.key --cert /tmp/server.crt'

sleep 5

log "Verify we have received the data in mqtt-source-1 topic"
playground topic consume --topic mqtt-source-1 --min-expected-messages 1 --timeout 60