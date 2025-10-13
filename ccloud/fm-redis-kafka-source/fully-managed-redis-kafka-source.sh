#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic redis_users_source
sleep 3
playground topic create --topic redis_users_source
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

connector_name="RedisKafkaSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Adding JSON data to Redis"
docker exec -i redis redis-cli << EOF
SET users:1001 '{"id":1001,"name":"John Doe","email":"john.doe@example.com","age":30,"city":"New York"}'
SET users:1002 '{"id":1002,"name":"Jane Smith","email":"jane.smith@example.com","age":25,"city":"Los Angeles"}'
SET users:1003 '{"id":1003,"name":"Bob Johnson","email":"bob.johnson@example.com","age":35,"city":"Chicago"}'
EOF

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
	"connector.class": "RedisKafkaSource",
	"name": "$connector_name",
	"kafka.auth.mode": "KAFKA_API_KEY",
	"kafka.api.key": "$CLOUD_KEY",
	"kafka.api.secret": "$CLOUD_SECRET",
	"output.data.format" : "AVRO",
	"redis.host": "$NGROK_HOSTNAME",
	"redis.port": "$NGROK_PORT",
	"redis.server.mode": "Standalone",
	"source.type": "KEYS",
	"kafka.topic": "redis_users_source",
	"redis.keys.pattern": "users:*",
    "keys.batch.size": "1",
	"tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 5

log "Verifying topic redis_users_source"
playground topic consume --topic redis_users_source --min-expected-messages 3 --timeout 60


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name