#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic orders
sleep 3
playground topic create --topic orders --nb-partitions 1
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

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 --forced-value '{"measurement": "orders", "id": 999, "product": "foo", "quantity": 100, "price": 50}' << 'EOF'
{
  "fields": [
    {
      "name": "measurement",
      "type": "string"
    },
    {
      "name": "id",
      "type": "int"
    },
    {
      "name": "product",
      "type": "string"
    },
    {
      "name": "quantity",
      "type": "int"
    },
    {
      "name": "price",
      "type": "float"
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

connector_name="InfluxDB2Sink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "InfluxDB2Sink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "input.data.format": "AVRO",
  "influxdb.url": "http://$NGROK_HOSTNAME:$NGROK_PORT",
  "influxdb.token": "my-super-secret-auth-token",
  "influxdb.org.id": "acme",
  "influxdb.bucket": "mybucket",
  "topics": "orders",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

sleep 10

log "Verify that order is in influxdb2"
docker exec influxdb2 influx config create --config-name acmeconfig --host-url http://localhost:8086 --org acme --token my-super-secret-auth-token --active  
docker exec influxdb2 influx query 'from(bucket:"mybucket") |> range(start:-100m)'


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name