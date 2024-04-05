#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic influx_mybucket
sleep 3
playground topic create --topic influx_mybucket --nb-partitions 1
set -e

docker compose build
docker compose down -v --remove-orphans
docker compose up -d

sleep 5

log "Insert data in bucket mybucket"
docker exec influxdb2 influx config create --config-name acmeconfig --host-url http://localhost:8086 --org acme --token my-super-secret-auth-token --active  
docker exec influxdb2  influx write -b mybucket -o acme -p s 'myMeasurement,host=myHost testField="testData" 1556896326'

log "Verifying data in mybucket"
docker exec influxdb2 influx query 'from(bucket:"mybucket") |> range(start:-100m)'

log "Getting ngrok hostname and port"
NGROK_URL=$(curl --silent http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url')
NGROK_HOSTNAME=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 1)
NGROK_PORT=$(echo $NGROK_URL | cut -d "/" -f3 | cut -d ":" -f 2)

connector_name="InfluxDB2Source_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
     "connector.class": "InfluxDB2Source",
     "name": "$connector_name",
     "kafka.auth.mode": "KAFKA_API_KEY",
     "kafka.api.key": "$CLOUD_KEY",
     "kafka.api.secret": "$CLOUD_SECRET",
     "output.data.format": "JSON",
     "influxdb.url": "http://$NGROK_HOSTNAME:$NGROK_PORT",
     "influxdb.token": "my-super-secret-auth-token",
     "influxdb.org.id": "acme",
     "influxdb.bucket": "mybucket",
     "topic.prefix": "influx_",
     "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

sleep 10

log "Verifying topic influx_mybucket"
playground topic consume --topic influx_mybucket --min-expected-messages 1 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name
