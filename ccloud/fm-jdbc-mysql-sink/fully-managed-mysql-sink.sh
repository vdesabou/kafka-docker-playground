#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment


set +e
playground topic delete --topic mysqlorders
set -e


log "Sending messages to topic mysqlorders"
playground topic produce -t mysqlorders --nb-messages 1 << 'EOF'
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

playground topic produce -t mysqlorders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
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

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

get_ngrok_url

connector_name="MySqlSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MySqlSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "connection.host": "$NGROK_HOSTNAME",
  "connection.port": "$NGROK_PORT",
  "connection.user": "user",
  "connection.password": "password",
  "db.name": "mydb",
  "input.data.format": "AVRO",
  "topics": "mysqlorders",
  "insert.mode": "INSERT",
  "auto.create": "true",
  "auto.evolve": "true",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground db wait-for-rows --table mysqlorders --min-expected-rows 2

log "Describing the mysqlorders table in DB 'mydb':"
playground db sql << 'EOF'
describe mysqlorders;
EOF

log "Show content of mysqlorders table:"
playground db sql > /tmp/result.log 2>&1 << 'EOF'
select * from mysqlorders;
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name