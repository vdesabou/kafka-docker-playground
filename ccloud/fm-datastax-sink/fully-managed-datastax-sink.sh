#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

log "Waiting for Cassandra to be ready..."
for i in {1..60}; do
  if docker exec cassandra cqlsh -u cassandra -p cassandra -e "SELECT now() FROM system.local;" > /dev/null 2>&1; then
    log "✅ Cassandra is ready!"
    break
  fi
  if [ $i -eq 60 ]; then
    logerror "❌ Cassandra did not become ready after 180 seconds"
    exit 1
  fi
  sleep 3
done

log "Getting local datacenter name"
DATACENTER=$(docker exec cassandra cqlsh -u cassandra -p cassandra -e "SELECT data_center FROM system.local;" | head -4 | tail -1 | tr -d ' ')
log "Local datacenter is $DATACENTER"

log "Creating keyspace ks and table ks.orders"
docker exec -i cassandra cqlsh -u cassandra -p cassandra << EOF
CREATE KEYSPACE IF NOT EXISTS ks WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
CREATE TABLE IF NOT EXISTS ks.orders (id int PRIMARY KEY, product text, quantity int, price double);
EOF

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
playground topic delete --topic orders
sleep 3
playground topic create --topic orders --nb-partitions 1
set -e

log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 10 --forced-value '{"id":%g,"product":"product%g","quantity":%g,"price":50.0}' << 'EOF'
{
  "type": "record",
  "name": "order",
  "fields": [
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
      "type": "double"
    }
  ]
}
EOF

connector_name="DataStaxSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "DataStaxSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "orders",
  "input.data.format": "AVRO",
  "deployment.type": "Apache Cassandra or DSE",
  "contactPoints": "$NGROK_HOSTNAME",
  "port": "$NGROK_PORT",
  "loadBalancing.localDc": "$DATACENTER",
  "auth.provider": "PLAIN",
  "auth.username": "cassandra",
  "auth.password": "cassandra",
  "mapping.map": "{\"orders.ks.orders\":\"id=value.id, product=value.product, quantity=value.quantity, price=value.price\"}",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 15

playground connector show-lag --connector $connector_name

log "Verify data is in Cassandra table ks.orders"
docker exec cassandra cqlsh -u cassandra -p cassandra -e "SELECT * FROM ks.orders;" > /tmp/result.log 2>&1
cat /tmp/result.log
grep "(10 rows)" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
