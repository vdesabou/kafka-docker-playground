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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

set +e
log "Removing ClickHouse database playground, if applicable"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure -q 'DROP DATABASE IF EXISTS playground'"
set -e

log "Creating ClickHouse database called playground"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure -q 'CREATE DATABASE IF NOT EXISTS playground'"

log "Creating ClickHouse table called clickhouse_measures"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure --database "playground" -q \"CREATE TABLE IF NOT EXISTS clickhouse_measures (measurement String, id Int32, product String, quantity Int32, price Float32) ENGINE = MergeTree() ORDER BY id\""

# from https://support.confluent.io/hc/en-us/articles/46567287376404-What-can-cause-a-ClickHouse-Sink-connector-on-Confluent-Cloud-to-fail-with-Connection-to-ClickHouse-is-not-active-Error
echo 'SELECT 1' | curl -H "X-ClickHouse-User: $CLICKHOUSE_CLOUD_USERNAME" -H "X-ClickHouse-Key: $CLICKHOUSE_CLOUD_PASSWORD" "https://$CLICKHOUSE_CLOUD_HOSTNAME:8443/?database=playground" -d @-
echo "SELECT name FROM system.tables WHERE database='playground' AND name='clickhouse_measures'" | curl -H "X-ClickHouse-User: $CLICKHOUSE_CLOUD_USERNAME" -H "X-ClickHouse-Key: $CLICKHOUSE_CLOUD_PASSWORD" "https://$CLICKHOUSE_CLOUD_HOSTNAME:8443/?database=playground" -d @-

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

log "Creating clickhouse sink connector"
playground connector create-or-update --connector clickhouse-sink << EOF
{
  "connector.class": "com.clickhouse.kafka.connect.ClickHouseSinkConnector",
  "hostname": "$CLICKHOUSE_CLOUD_HOSTNAME",
  "port": "8443",
  "ssl": "true",
  "jdbcConnectionProperties": "sslmode=STRICT",
  "username": "$CLICKHOUSE_CLOUD_USERNAME",
  "password": "$CLICKHOUSE_CLOUD_PASSWORD",
  "database": "playground",
  "topics": "clickhouse_measures",
  "tasks.max" : "1"
}
EOF

sleep 10

log "Verify that data is in clickhouse"
docker run -i --rm clickhouse/clickhouse-server bash -c "clickhouse-client --host $CLICKHOUSE_CLOUD_HOSTNAME --port 9440 --user $CLICKHOUSE_CLOUD_USERNAME --password \"${CLICKHOUSE_CLOUD_PASSWORD}\" --secure --database "playground" --query \"SELECT * FROM clickhouse_measures\""
