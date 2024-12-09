#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

mkdir -p ../../ccloud/fm-rabbitmq-source/security
cd ../../ccloud/fm-rabbitmq-source/security
playground tools certs-create --output-folder "$PWD" --container connect --container rabbitmq
base64_truststore=$(cat $PWD/kafka.connect.truststore.jks | base64 | tr -d '\n')
base64_keystore=$(cat $PWD/kafka.connect.keystore.jks | base64 | tr -d '\n')
cd -

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



docker compose -f docker-compose.ssl.yml build
docker compose -f docker-compose.ssl.yml down -v --remove-orphans
docker compose -f docker-compose.ssl.yml up -d --quiet-pull

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

connector_name="RabbitMQSourceSSL_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

sleep 6

log "Send message to RabbitMQ in myqueue"
docker exec rabbitmq_producer bash -c "python /producer.py myqueue 5"

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "RabbitMQSource",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "kafka.topic": "rabbitmq",
     "rabbitmq.host" : "$NGROK_HOSTNAME",
     "rabbitmq.port" : "$NGROK_PORT",
     "rabbitmq.username": "myuser",
     "rabbitmq.password" : "mypassword",
     "rabbitmq.queue": "myqueue",

     "rabbitmq.security.protocol": "SSL",
     "rabbitmq.https.ssl.truststorefile": "data:text/plain;base64,$base64_truststore",
     "rabbitmq.https.ssl.truststore.password": "confluent",
     "rabbitmq.https.ssl.keystorefile": "data:text/plain;base64,$base64_keystore",
     "rabbitmq.https.ssl.keystore.password": "confluent",

     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Verifying topic rabbitmq"
playground topic consume --topic rabbitmq --min-expected-messages 5 --timeout 60

# CreateTime:2024-03-26 16:38:53.274|Partition:0|Offset:4|Headers:rabbitmq.consumer.tag:amq.ctag-W89VdFXz19PMBPcz1rZb1g,rabbitmq.content.type:application/json,rabbitmq.content.encoding:utf-8,rabbitmq.delivery.mode:1,rabbitmq.priority:1,rabbitmq.correlation.id:null,rabbitmq.reply.to:null,rabbitmq.expiration:null,rabbitmq.message.id:4,rabbitmq.timestamp:null,rabbitmq.type:null,rabbitmq.user.id:null,rabbitmq.app.id:null,rabbitmq.delivery.tag:5,rabbitmq.redeliver:false,rabbitmq.exchange:,rabbitmq.routing.key:myqueue|Key:4|Value:{"id": 4, "body": "010101010101010101010101010101010101010101010101010101010101010101010"}|ValueSchemaId:

#log "Consume messages in RabbitMQ"
#docker exec -it rabbitmq_consumer bash -c "python /consumer.py myqueue"

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
