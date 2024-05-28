#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

cd ../../ccloud/fm-rabbitmq-sink/security
log "🔐 Generate keys and certificates used for SSL"
docker run -u0 --rm -v $PWD:/tmp ${CP_CONNECT_IMAGE}:${CONNECT_TAG} bash -c "/tmp/certs-create.sh > /dev/null 2>&1 && chown -R $(id -u $USER):$(id -g $USER) /tmp/ && chmod a+r /tmp/*"
cd -

display_ngrok_warning

bootstrap_ccloud_environment


set +e
playground topic delete --topic rabbitmq-messages
sleep 3
playground topic create --topic rabbitmq-messages
set -e

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

sleep 5

log "Create RabbitMQ exchange, queue and binding"
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare exchange name=exchange1 type=direct
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare queue name=queue1 durable=true
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword -V / declare binding source=exchange1 destination=queue1 routing_key=rkey1


log "Sending messages to topic rabbitmq-messages"
playground topic produce -t rabbitmq-messages --nb-messages 10 << 'EOF'
%g
EOF

connector_name="RabbitMQSinkSSL_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

base64_truststore=$(cat $PWD/security/kafka.connect.truststore.jks | base64 | tr -d '\n')
base64_keystore=$(cat $PWD/security/kafka.connect.keystore.jks | base64 | tr -d '\n')

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "RabbitMQSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "rabbitmq.host" : "$NGROK_HOSTNAME",
  "rabbitmq.port" : "$NGROK_PORT",
  "rabbitmq.username": "myuser",
  "rabbitmq.password" : "mypassword",
  "rabbitmq.queue": "myqueue",
  "rabbitmq.exchange": "exchange1",
  "rabbitmq.routing.key": "rkey1",
  "rabbitmq.delivery.mode": "persistent",
  "topics" : "rabbitmq-messages",

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

log "Check messages received in RabbitMQ"
docker exec -i rabbitmq rabbitmqadmin -u myuser -p mypassword get queue=queue1 count=10 > /tmp/result.log  2>&1
cat /tmp/result.log
grep "rkey1" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name