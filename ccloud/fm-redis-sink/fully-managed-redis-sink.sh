#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic redis_topic
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull
 
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


log "Sending messages to topic redis_topic"
playground topic produce -t redis_topic --nb-messages 3 --key "key1" << 'EOF'
value%g
EOF


connector_name="RedisSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "RedisSink",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "input.data.format": "STRING",
     "redis.hostname": "$NGROK_HOSTNAME",
     "redis.portnumber": "$NGROK_PORT",
     "topics": "redis_topic",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify data is in Redis"
# list the keys of all redis databases (the database used depends on the connector), retry for up to 2 minutes
for i in $(seq 1 24)
do
     playground --output-level WARN container exec --container redis --command "for db in \$(seq 0 15); do redis-cli -n \$db KEYS '*'; done" > /tmp/result.log  2>&1
     if grep -q "__kafka.offset.redis_topic.0" /tmp/result.log
     then
          break
     fi
     log "__kafka.offset.redis_topic.0 not found yet in redis, retrying in 5 seconds"
     sleep 5
done
cat /tmp/result.log
grep "__kafka.offset.redis_topic.0" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name