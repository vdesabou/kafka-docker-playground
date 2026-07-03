#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_solace () {
     MAX_WAIT=240
     log "⌛ Waiting up to $MAX_WAIT seconds for Solace to startup"
     # Use playground logs so readiness wait works for both Docker and CFK environments.
     playground container logs --container solace --wait-for-log "Starting solace process" --max-wait "$MAX_WAIT"
     playground container logs --container solace --wait-for-log "Launching solacedaemon" --max-wait "$MAX_WAIT"
     log "Solace is started!"
     sleep 30
}

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

wait_for_solace
log "Solace UI is accessible at http://127.0.0.1:8080 (admin/admin)"

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

set +e
playground topic delete --topic from-solace-messages
sleep 3
playground topic create --topic from-solace-messages --nb-partitions 1
set -e

# Setting message.timestamp.type=LogAppendTime otherwise we have CreateTime:0
playground topic alter --topic from-solace-messages --add-config message.timestamp.type=LogAppendTime

connector_name="SolaceSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e


log "Create the queue connector-quickstart in the default Message VPN using CLI"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/create_queue_cmd"


log "Publish messages to the Solace queue using the REST endpoint"

for i in 1000 1001 1002
do
     curl -X POST -d "m1" http://localhost:9000/Queue/connector-quickstart -H "Content-Type: text/plain" -H "Solace-Message-ID: $i"
done



log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "SolaceSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "input.data.format": "STRING",

    "kafka.topic": "from-solace-messages",
    "solace.host": "smf://$NGROK_HOSTNAME:$NGROK_PORT",
    "solace.username": "admin",
    "solace.password": "admin",
    "jms.destination.type": "queue",
    "jms.destination.name": "connector-quickstart",

    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Verifying topic from-solace-messages"
playground topic consume --topic from-solace-messages --min-expected-messages 3 --timeout 60

sleep 5

log "Asserting that Solace queue connector-quickstart is empty after connector processing"
log "This tests that commitRecord API properly deletes messages from external system"
QUEUE_MSG_COUNT=$(curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart | jq -r '.data.msgSpoolUsage // empty')

if [ -z "$QUEUE_MSG_COUNT" ]; then
    logerror "❌ Failed to retrieve queue message count from Solace"
    exit 1
fi

log "Current message spool usage for connector-quickstart: $QUEUE_MSG_COUNT bytes"

if [ "$QUEUE_MSG_COUNT" -eq 0 ]; then
    log "✅ SUCCESS: Solace queue connector-quickstart is empty - messages were successfully consumed and deleted"
else
    logerror "❌ FAILURE: Messages still remain in Solace queue connector-quickstart (spool usage: $QUEUE_MSG_COUNT bytes) - messages were not deleted"
    log "Displaying queue statistics:"
    curl -s -u admin:admin http://localhost:8080/SEMP/v2/monitor/msgVpns/default/queues/connector-quickstart | jq '.'
    exit 1
fi

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name