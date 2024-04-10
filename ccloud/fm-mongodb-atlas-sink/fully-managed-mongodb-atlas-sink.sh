#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


MONGODB_ATLAS_HOST=${MONGODB_ATLAS_HOST:-$1}
MONGODB_ATLAS_USER=${MONGODB_ATLAS_USER:-$2}
MONGODB_ATLAS_PASSWORD=${MONGODB_ATLAS_PASSWORD:-$3}

if [ -z "$MONGODB_ATLAS_HOST" ]
then
     logerror "MONGODB_ATLAS_HOST is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$MONGODB_ATLAS_USER" ]
then
     logerror "MONGODB_ATLAS_USER is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$MONGODB_ATLAS_PASSWORD" ]
then
     logerror "MONGODB_ATLAS_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

bootstrap_ccloud_environment

set +e
playground topic delete --topic orders
set -e

playground topic create --topic orders

log "Drop customers collection, it might fail"
set +e
docker run --quiet --rm -i mongo:latest mongosh "mongodb+srv://$MONGODB_ATLAS_HOST/" --apiVersion 1 --username $MONGODB_ATLAS_USER --password $MONGODB_ATLAS_PASSWORD << EOF
use inventory;
db.customers.drop();
EOF
set -e


log "Sending messages to topic orders"
playground topic produce -t orders --nb-messages 1 << 'EOF'
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

playground topic produce -t orders --nb-messages 1 --forced-value '{"id":2,"product":"foo","quantity":2,"price":0.86583304}' << 'EOF'
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

connector_name="MongoDbAtlasSink_$USER"
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
     "topics":"orders",
     "connection.host": "$MONGODB_ATLAS_HOST",
     "connection.user": "$MONGODB_ATLAS_USER",
     "connection.password": "$MONGODB_ATLAS_PASSWORD",
     "database": "inventory",
     "collection": "customers",
     "input.data.format": "AVRO",
     "tasks.max": "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 600

sleep 10

log "View record"
docker run --quiet --rm -i mongo:latest mongosh "mongodb+srv://$MONGODB_ATLAS_HOST/" --apiVersion 1 --username $MONGODB_ATLAS_USER --password $MONGODB_ATLAS_PASSWORD << EOF
use inventory
db.customers.find().pretty();
EOF

docker run --quiet --rm -i mongo:latest mongosh "mongodb+srv://$MONGODB_ATLAS_HOST/" --apiVersion 1 --username $MONGODB_ATLAS_USER --password $MONGODB_ATLAS_PASSWORD << EOF > output.txt
use inventory
db.customers.find().pretty();
EOF
grep "foo" output.txt
rm output.txt

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name