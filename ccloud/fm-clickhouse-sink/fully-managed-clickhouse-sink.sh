#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic clickhouse_measures
sleep 3
playground topic create --topic clickhouse_measures --nb-partitions 1
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 5

log "Creating ClickHouse table"
playground container exec --container "clickhouse" --command "clickhouse-client -u myuser --password mypassword -q \"CREATE DATABASE IF NOT EXISTS default\""
playground container exec --container "clickhouse" --command "clickhouse-client -u myuser --password mypassword -q \"CREATE TABLE IF NOT EXISTS clickhouse_measures (measurement String, id Int32, product String, quantity Int32, price Float32) ENGINE = MergeTree() ORDER BY id\""

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

log "Sending messages to topic clickhouse_measures"
playground topic produce -t clickhouse_measures --nb-messages 1 --forced-value '{"measurement": "clickhouse_measures", "id": 999, "product": "foo", "quantity": 100, "price": 50}' << 'EOF'
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

connector_name="ClickHouseSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "ClickHouseSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "input.data.format": "AVRO",
  "hostname": "$NGROK_HOSTNAME",
  "port": "$NGROK_PORT",
  "ssl": "false",
  "username": "myuser",
  "password": "mypassword",
  "topics": "clickhouse_measures",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify that data is in clickhouse"
playground container exec --container "clickhouse" --command "clickhouse-client -u myuser --password mypassword -q \"SELECT * FROM clickhouse_measures\""

# playground container exec --container "clickhouse" --command "cat /var/log/clickhouse-server/clickhouse-server.log"
# playground container exec --container "clickhouse" --command "cat /var/log/clickhouse-server/clickhouse-server.err.log"

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name