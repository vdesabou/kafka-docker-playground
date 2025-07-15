#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic product"
playground topic produce -t product --nb-messages 3 << 'EOF'
{
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
    },
    {
      "name": "tags",
      "type": {
        "name": "tags",
        "type": "map",
        "values": "string"
      }
    }
  ],
  "name": "myrecord",
  "type": "record"
}
EOF

log "Creating product InfluxDB sink connector using SMT for fun"
playground connector create-or-update --connector influxdb-sink  << EOF
{
  "connector.class": "io.confluent.influxdb.InfluxDBSinkConnector",
  "tasks.max": "1",
  "influxdb.url": "http://influxdb:8086",
  "topics": "product",
  "transforms": "InsertField,RenameField",
  "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
  "transforms.InsertField.static.field": "measurement",
  "transforms.InsertField.static.value": "product",
  "transforms.RenameField.type": "org.apache.kafka.connect.transforms.ReplaceField\$Value",
  "transforms.RenameField.renames": "product:name"
}
EOF

sleep 10

log "Verify product data is in InfluxDB with its tags"
docker exec influxdb influx -database product -execute 'select * from product' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "product" /tmp/result.log
