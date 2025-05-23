#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



log "Creating users topic"
set +e
playground topic delete --topic users
sleep 3
playground topic create --topic users
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


playground container logs --container opensearch-dashboards --wait-for-log "Server running at http://0.0.0.0:5601" --max-wait 300
log "Navigate to http://127.0.0.1:5601 (admin/P@szw0rd1!) for OpenSearch Dashboards"

connector_name="OpenSearchSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "OpenSearchSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "input.data.format": "AVRO",
  "topics": "users",
  "instance.url": "http://$NGROK_HOSTNAME:$NGROK_PORT",
  "auth.type": "BASIC",
  "connection.user": "admin",
  "connection.password": "P@szw0rd1!",
  "indexes.num": "1",
  "index1.name" : "users_index",
  "index1.topic": "users",
  "request.method": "POST",
  "retry.backoff.policy": "CONSTANT_VALUE",
  "max.retries": "1",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Sending messages to topic users"
playground topic produce -t users --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

sleep 20

log "Check that the data is available in opensearch in users_index"
curl -XGET -u 'admin:P@szw0rd1!' 'http://localhost:9200/users_index/_search?pretty' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "f1" /tmp/result.log | grep "value1"
grep "f1" /tmp/result.log | grep "value10"

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name