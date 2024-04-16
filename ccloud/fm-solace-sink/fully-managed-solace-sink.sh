#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_solace () {
     MAX_WAIT=240
     CUR_WAIT=0
     log "⌛ Waiting up to $MAX_WAIT seconds for Solace to startup"
     docker container logs solace > /tmp/out.txt 2>&1
     while ! grep "Running pre-startup checks" /tmp/out.txt > /dev/null;
     do
          sleep 10
          docker container logs solace > /tmp/out.txt 2>&1
          CUR_WAIT=$(( CUR_WAIT+10 ))
          if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
               echo -e "\nERROR: The logs in all connect containers do not show 'Running pre-startup checks' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
               exit 1
          fi
     done
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
    if [ "$status" = "running" ]; then
      break
    fi
  fi
  log "Waiting for container ngrok to start..."
  sleep 5
done
log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

set +e
playground topic delete --topic solace-topic
sleep 3
playground topic create --topic solace-topic --nb-partitions 3
set -e

connector_name="SolaceSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e


log "Sending messages to topic solace-topic"
playground topic produce -t solace-topic --nb-messages 10 << 'EOF'
%g
EOF


log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "SolaceSink",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "input.data.format": "STRING",
     "topics": "solace-topic",
     "solace.host": "smf://$NGROK_HOSTNAME:$NGROK_PORT",
     "solace.username": "admin",
     "solace.password": "admin",
     "jms.destination.type": "queue",
     "jms.destination.name": "connector-quickstart",
     "solace.dynamic.durables": "true",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

sleep 30

log "Confirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI"
docker exec solace bash -c "/usr/sw/loads/currentload/bin/cli -A -s cliscripts/show_queue_cmd" > /tmp/result.log  2>&1
cat /tmp/result.log
grep "Message VPN" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name