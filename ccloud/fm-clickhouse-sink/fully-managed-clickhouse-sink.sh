#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

CLICKHOUSE_CLOUD_USERNAME=${CLICKHOUSE_CLOUD_USERNAME:-$1}
CLICKHOUSE_CLOUD_PASSWORD=${CLICKHOUSE_CLOUD_PASSWORD:-$2}
CLICKHOUSE_CLOUD_HOSTNAME=${CLICKHOUSE_CLOUD_HOSTNAME:-$3}

if [ -z "$CLICKHOUSE_CLOUD_USERNAME" ]
then
     logerror "CLICKHOUSE_CLOUD_USERNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$CLICKHOUSE_CLOUD_PASSWORD" ]
then
     logerror "CLICKHOUSE_CLOUD_PASSWORD is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$CLICKHOUSE_CLOUD_HOSTNAME" ]
then
     logerror "CLICKHOUSE_CLOUD_HOSTNAME is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

bootstrap_ccloud_environment

set +e
playground topic delete --topic clickhouse_measures
sleep 3
playground topic create --topic clickhouse_measures --nb-partitions 1
set -e


sleep 5

set +e
log "Removing ClickHouse database playground, if applicable"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure -q 'DROP DATABASE IF EXISTS playground'"
set -e

log "Creating ClickHouse database called playground"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure -q 'CREATE DATABASE IF NOT EXISTS playground'"

log "Creating ClickHouse table called clickhouse_measures"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure --database "playground" -q \"CREATE TABLE IF NOT EXISTS clickhouse_measures (measurement String, id Int32, product String, quantity Int32, price Float32) ENGINE = MergeTree() ORDER BY id\""


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
  "hostname": "$CLICKHOUSE_CLOUD_HOSTNAME",
  "port": "8443",
  "username": "$CLICKHOUSE_CLOUD_USERNAME",
  "password": "$CLICKHOUSE_CLOUD_PASSWORD",
  "database": "playground",
  "topics": "clickhouse_measures",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify that data is in clickhouse"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure --database "playground" --query \"SELECT * FROM clickhouse_measures\""

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name