#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

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
playground connector create-or-update --connector influxdb-sink << EOF
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
