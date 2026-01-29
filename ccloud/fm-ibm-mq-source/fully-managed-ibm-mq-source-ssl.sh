#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic MyKafkaTopicName
set -e

mkdir -p ../../ccloud/fm-ibm-mq-source/security
cd ../../ccloud/fm-ibm-mq-source/security
playground tools certs-create --output-folder "$PWD" --container ibmmq
cd -

docker compose -f docker-compose-ssl.yml build
docker compose -f docker-compose-ssl.yml down -v --remove-orphans
docker compose -f docker-compose-ssl.yml up -d --quiet-pull

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

sleep 10

log "Verify TLS is active on IBM MQ: it should display SSLCIPH(ANY_TLS12)"
docker exec -i ibmmq runmqsc QM1 << EOF
DISPLAY CHANNEL(DEV.APP.SVRCONN)
EOF

connector_name="IbmMQSourceSSL_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

base64_truststore=$(cat ../../ccloud/fm-ibm-mq-source/security/kafka.ibmmq.truststore.jks | base64 | tr -d '\n')

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "IbmMQSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "output.data.format": "AVRO",
    "kafka.topic": "MyKafkaTopicName",
    "mq.hostname": "$NGROK_HOSTNAME",
    "mq.port": "$NGROK_PORT",
    "mq.transport.type": "client",
    "mq.queue.manager": "QM1",
    "mq.channel": "DEV.APP.SVRCONN",
    "mq.username": "app",
    "mq.password": "passw0rd",
    "jms.destination.name": "DEV.QUEUE.1",
    "jms.destination.type": "queue",
    "mq.tls.truststore.location": "data:text/plain;base64,$base64_truststore",
    "mq.tls.truststore.password": "confluent",
    "mq.ssl.cipher.suite":"TLS_RSA_WITH_AES_128_CBC_SHA256",

    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Sending messages to DEV.QUEUE.1 JMS queue:"
docker exec -i ibmmq /opt/mqm/samp/bin/amqsput DEV.QUEUE.1 << EOF
Message 1
Message 2

EOF

sleep 5

log "Verify we have received the data in MyKafkaTopicName topic"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name