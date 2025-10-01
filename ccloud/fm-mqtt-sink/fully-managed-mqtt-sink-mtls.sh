#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ../../ccloud/fm-mqtt-source/security
cd ../../ccloud/fm-mqtt-source/security
playground tools certs-create --output-folder "$PWD" --container connect --container mosquitto --verbose
base64_truststore=$(cat $PWD/kafka.connect.truststore.jks | base64 | tr -d '\n')
base64_keystore=$(cat $PWD/kafka.connect.keystore.jks | base64 | tr -d '\n')
cd -

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic mqtt_sink_messages
set -e

docker compose -f docker-compose.mtls.yml build
docker compose -f docker-compose.mtls.yml down -v --remove-orphans
docker compose -f docker-compose.mtls.yml up -d --quiet-pull

sleep 5

log "Waiting for ngrok to start"
while true
do
  container_id=$(docker ps -q -f name=ngrok)
  if [ -n "$container_id" ]
  then
    status=$(docker inspect --format '{{.State.Status}}' $container_id)
    if [ "$status" = "running" ]
    then
      log "Getting ngrok hostname and port"
      NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
      NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
      NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

      if ! [[ $NGROK_PORT =~ ^[0-9]+$ ]]
      then
        log "NGROK_PORT is not a valid number, keep retrying..."
        continue
      else 
        break
      fi
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done

connector_name="MqttSinkMTLS_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

playground topic produce -t mqtt_sink_messages --nb-messages 3 --forced-value '"This is my message"' << 'EOF'
"string"
EOF

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "MqttSink",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "input.data.format": "AVRO",
     "topics": "mqtt_sink_messages",
     "mqtt.qos": "2",
     "mqtt.server.uri" : "ssl://$NGROK_HOSTNAME:$NGROK_PORT",
     "mqtt.topics":"my-mqtt-topic",
     "mqtt.username": "myuser",
     "mqtt.password": "mypassword",

     "mqtt.ssl.trust.store.file": "data:text/plain;base64,$base64_truststore",
     "mqtt.ssl.trust.store.password": "confluent",
     "mqtt.ssl.key.store.file": "data:text/plain;base64,$base64_keystore",
     "mqtt.ssl.key.store.password": "confluent",
     "mqtt.ssl.key.password": "confluent",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


sleep 5

log "Verify we have received messages in MQTT sink-messages topic"
timeout 60 docker exec mosquitto sh -c 'mosquitto_sub -h localhost -p 1883 -u "myuser" -P "mypassword" -t "mqtt_sink_messages" -C 1' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "This is my message" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name