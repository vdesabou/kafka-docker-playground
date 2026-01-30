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

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

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

log "Setup IBM MQ for EOS: topic and permissions"
docker exec -i ibmmq runmqsc QM1 << EOF
DEFINE TOPIC('MY.MQ.STATE.TOPIC') TOPICSTR('ibm-mq-source-state-topic')
EOF

docker exec -u 0 ibmmq setmqaut -m QM1 -t topic -n MY.MQ.STATE.TOPIC -p app +sub +pub +dsp
docker exec -u 0 ibmmq setmqaut -m QM1 -t q -n SYSTEM.DEFAULT.MODEL.QUEUE -p app +get +dsp +inq

docker exec -i ibmmq runmqsc QM1 << EOF
REFRESH SECURITY TYPE(AUTHSERV)
EOF

connector_name="IbmMQSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

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

    "state.topic.name": "ibm-mq-source-state-topic",
    "transaction.boundary": "connector",

    "jms.destination.name": "DEV.QUEUE.1",
    "jms.destination.type": "queue",
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

sleep 15

log "Verify we have received the data in MyKafkaTopicName topic using --isolation-level read_committed"
playground topic consume --topic MyKafkaTopicName --min-expected-messages 2 --timeout 60 --isolation-level read_committed

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name