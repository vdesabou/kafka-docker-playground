#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

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

docker exec -i connect kafka-avro-console-consumer \
     --bootstrap-server broker:9092 \
     --property schema.registry.url=http://schema-registry:8081 \
     --topic orders \
     --from-beginning \
     --max-messages=1

log "Creating InfluxDB sink connector"
playground connector create-or-update --connector influxdb-sink --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
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
