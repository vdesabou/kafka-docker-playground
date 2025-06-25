#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic test-travel-sample
sleep 3
playground topic create --topic test-travel-sample --nb-partitions 1
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 15



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

log "Creating Couchbase cluster"
docker exec couchbase bash -c "/opt/couchbase/bin/couchbase-cli cluster-init --cluster-username Administrator --cluster-password password --services=data,index,query"
log "Install Couchbase bucket example travel-sample"
curl -X POST -u Administrator:password http://localhost:8091/sampleBuckets/install -d '["travel-sample"]'

connector_name="CouchbaseSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "CouchbaseSource",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "output.data.format": "JSON",
  "couchbase.seed.nodes": "$NGROK_HOSTNAME:$NGROK_PORT",
  "couchbase.bucket": "travel-sample",
  "couchbase.topic": "test-travel-sample",
  "couchbase.username": "Administrator",
  "couchbase.password": "password",
  "couchbase.source.handler": "com.couchbase.connect.kafka.handler.source.DefaultSchemaSourceHandler",
  "couchbase.stream.from": "SAVED_OFFSET_OR_BEGINNING",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Verifying topic test-travel-sample"
playground topic consume --topic test-travel-sample --min-expected-messages 2 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name