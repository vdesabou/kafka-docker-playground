#!/bin/bash
# To enable exactly once semantics (EOS), you must manually create a unique queue for each connector
# to serve as its offset store. To ensure a single active consumer, the queue must be configured in
# exclusive mode by setting the DEFSOPT (Default open option) attribute to EXCLUSIVE.
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic sink-messages
set -e

log "Creating sink-messages topic in Confluent Cloud"
set +e
playground topic create --topic sink-messages
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

log "Setup IBM MQ for EOS: queue KAFKA.OFFSETS.QUEUE"
# Create offset queue for EOS with exclusive mode enabled
docker exec -i ibmmq runmqsc QM1 << EOF
DEFINE QLOCAL(KAFKA.OFFSETS.QUEUE) DEFPSIST(YES) DEFSOPT(EXCL)
END
EOF

# Set appropriate permissions for the connector user to read, write and browse the offsets queue
docker exec -i ibmmq runmqsc QM1 << EOF
SET AUTHREC OBJTYPE(QUEUE) PROFILE('KAFKA.OFFSETS.QUEUE') PRINCIPAL('app') AUTHADD(GET,PUT,BROWSE,DSP,INQ)
END
EOF

log "Sending messages to topic sink-messages"
playground topic produce --topic sink-messages --nb-messages 1 << 'EOF'
This is my message
EOF

connector_name="IbmMqSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "IbmMqSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "input.data.format": "STRING",
    "topics": "sink-messages",
    "mq.hostname": "$NGROK_HOSTNAME",
    "mq.port": "$NGROK_PORT",
    "mq.transport.type": "client",
    "mq.queue.manager": "QM1",
    "mq.channel": "DEV.APP.SVRCONN",
    "mq.username": "app",
    "mq.password": "passw0rd",

    "exactly.once.enabled": "true",
    "mq.offsets.queue.name": "KAFKA.OFFSETS.QUEUE",

    "jms.destination.name": "DEV.QUEUE.1",
    "jms.destination.type": "queue",

    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify message received in DEV.QUEUE.1 queue"
docker exec ibmmq bash -c "/opt/mqm/samp/bin/amqsbcg DEV.QUEUE.1" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "my message" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name