#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



docker compose -f docker-compose.yml build
docker compose -f docker-compose.yml down -v --remove-orphans
docker compose -f docker-compose.yml up -d --quiet-pull

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

set +e
playground topic delete --topic http-topic-spaces
set -e

log "Creating http-topic-spaces topic in Confluent Cloud"
set +e
playground topic create --topic http-topic-spaces
set -e

connector_name="HttpSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

# log "Set webserver to reply with 200"
# curl -X PUT -H "Content-Type: application/json" --data '{"errorCode": 200}' http://localhost:9006/set-response-error-code
# curl -X PUT -H "Content-Type: application/json" --data '{"delay": 2000}' http://localhost:9006/set-response-time


log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "HttpSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "tasks.max" : "1",
    "output.data.format": "AVRO",
    "url": "http://$NGROK_HOSTNAME:$NGROK_PORT/wiki/rest/api/space",
    "topic.name.pattern":"http-topic-\${entityName}",
    "entity.names": "spaces",
    "http.offset.mode": "SIMPLE_INCREMENTING",
    "http.request.parameters": "start=\${offset}&limit=1",
    "http.initial.offset": "0",
    "http.response.data.json.pointer": "/results",
    "request.interval.ms": "1000"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify we have received the initial spaces in http-topic-spaces topic (expecting at least 15 spaces, 1 per page)"
playground topic consume --topic http-topic-spaces --min-expected-messages 15 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
