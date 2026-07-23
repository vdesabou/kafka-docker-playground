#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

function wait_for_solace () {
  MAX_WAIT=600
     log "⌛ Waiting up to $MAX_WAIT seconds for Solace to startup"
     # Use playground logs so readiness wait works for both Docker and CFK environments.
     playground container logs --container solace --wait-for-log "Running pre-startup checks" --max-wait "$MAX_WAIT"
     log "Solace is started!"
     sleep 30
}

function run_solace_cli_script_with_retry () {
  local script_name="$1"
  local description="$2"
  local output_file="${3:-/tmp/solace-cli-${script_name}.log}"
  local max_wait=300
  local cur_wait=0

  log "⌛ Waiting up to $max_wait seconds for Solace CLI to be ready for ${description}"
  while true
  do
    set +e
    playground container exec --container solace --command "bash -c \"/usr/sw/loads/currentload/bin/cli -A -s cliscripts/${script_name}\"" > "$output_file" 2>&1
    ret=$?
    set -e

    if [ $ret -eq 0 ]
    then
      log "Solace CLI is ready for ${description}"
      return
    fi

    if grep -E "SolOS startup in progress|Please try again later" "$output_file" > /dev/null 2>&1
    then
      sleep 10
      cur_wait=$((cur_wait + 10))
      if [[ "$cur_wait" -gt "$max_wait" ]]
      then
        logerror "Solace CLI is not ready for ${description} after ${max_wait} seconds"
        cat "$output_file"
        exit 1
      fi
      continue
    fi

    logerror "Solace CLI command for ${description} failed with a non-retryable error"
    cat "$output_file"
    exit 1
  done
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
wait_for_ccloud_connector_up $connector_name 180

sleep 30

log "Confirm the messages were delivered to the connector-quickstart queue in the default Message VPN using CLI"
run_solace_cli_script_with_retry "show_queue_cmd" "queue stats check" "/tmp/result.log"
cat /tmp/result.log
grep "10       0.00" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name