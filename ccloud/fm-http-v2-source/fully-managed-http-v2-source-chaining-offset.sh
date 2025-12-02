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
playground topic delete --topic http-source-topic-v2
set -e

log "Creating http-source-topic-v2 topic in Confluent Cloud"
set +e
playground topic create --topic http-source-topic-v2
set -e

connector_name="HttpSourceV2_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "HttpSourceV2",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "output.data.format": "AVRO",
    "tasks.max" : "1",

    "http.api.base.url": "http://$NGROK_HOSTNAME:$NGROK_PORT",
    "behavior.on.error": "FAIL",

    "apis.num": "1",
    "api1.http.api.path": "/test-index/_search",
    "api1.topics": "http-source-topic-v2",
    "api1.http.request.headers": "Content-Type: application/json",
    "api1.test.api": "false",
    "api1.http.offset.mode": "CHAINING",
    "api1.http.request.method": "POST",
    "api1.http.request.body": "{\\"size\\": 100, \\"sort\\": [{\\"@time\\": \\"asc\\"}], \\"search_after\\": [\${offset}]}",
    "api1.http.initial.offset": "1647948000000",
    "api1.http.response.data.json.pointer": "/hits/hits",
    "api1.http.offset.json.pointer": "/sort/0",
    "api1.request.interval.ms": "5000"
}
EOF
wait_for_ccloud_connector_up $connector_name 180


log "Wait 5 seconds for connector to start and fetch initial batch"
sleep 5

playground topic consume --topic http-source-topic-v2 --min-expected-messages 3 --timeout 10


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
