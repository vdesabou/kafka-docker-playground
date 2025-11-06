#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"


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

log "Creating InfluxDB sink connector"
playground connector create-or-update --connector influxdb-sink  << EOF
{
  "connector.class": "io.confluent.influxdb.InfluxDBSinkConnector",
  "tasks.max": "1",
  "influxdb.url": "http://influxdb:8086",
  "topics": "orders"
}
EOF

sleep 10

log "Verify that order is in InfluxDB"
docker exec influxdb influx -database orders -execute 'select * from orders' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "product" /tmp/result.log
