#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


NGROK_AUTH_TOKEN=${NGROK_AUTH_TOKEN:-$1}

display_ngrok_warning

bootstrap_ccloud_environment

set +e
playground topic delete --topic mongodb.orders
set -e

playground topic create --topic mongodb.orders

docker compose build
docker compose down -v --remove-orphans
docker compose up -d --quiet-pull

sleep 5

get_ngrok_url


log "Initialize MongoDB replica set"
playground db sql << 'EOF'
rs.initiate({_id: "myuser", members:[{_id: 0, host: "mongodb:27017"}]})
EOF

sleep 5

log "Create a user profile"
playground db sql << EOF
use admin
db.createUser(
{
user: "myuser",
pwd: "mypassword",
roles: ["dbOwner"]
}
)
EOF

sleep 2

log "Sending messages to topic mongodb.orders"
playground topic produce -t mongodb.orders --nb-messages 1 << 'EOF'
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

playground topic produce -t mongodb.orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
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


connector_name="MongoDbSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "MongoDbAtlasSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics":"mongodb.orders",
  "mongodb.instance.type": "MONGODB_SELF_MANAGED",
  "connection.host": "$NGROK_HOSTNAME:$NGROK_PORT",
  "connection.user": "myuser",
  "connection.password": "mypassword",
  "database": "inventory",
  "collection": "customers",
  "input.data.format": "AVRO",
  "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

playground db wait-for-rows --database inventory --table customers --min-expected-rows 2

log "View record"
playground db sql --database inventory > /tmp/result.log 2>&1 << 'EOF'
db.customers.find().pretty();
EOF
cat /tmp/result.log
grep "foo" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name