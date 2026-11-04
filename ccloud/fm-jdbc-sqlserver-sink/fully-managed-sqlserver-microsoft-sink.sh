#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment



set +e
playground topic delete --topic sqlserver_table
set -e

playground topic create --topic sqlserver_table

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 5

get_ngrok_url

connector_name="MicrosoftSqlServerSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MicrosoftSqlServerSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "input.data.format": "AVRO",
  "connection.host": "$NGROK_HOSTNAME",
  "connection.port": "$NGROK_PORT",
  "connection.user": "sa",
  "connection.password": "Password!",
  "db.name": "master",
  "topics": "sqlserver_table",
  "auto.create": "true",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Sending messages to topic sqlserver_table"
playground topic produce -t sqlserver_table --nb-messages 1 << 'EOF'
{
  "type": "record",
  "name": "myrecord",
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
      "type": "float"
    }
  ]
}
EOF

playground topic produce -t sqlserver_table --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
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
      "type": "float"
    }
  ]
}
EOF

playground db wait-for-rows --table sqlserver_table --min-expected-rows 2

log "Show content of sqlserver_table table:"
playground db sql > /tmp/result.log  2>&1 <<-EOF
select * from sqlserver_table
GO
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name