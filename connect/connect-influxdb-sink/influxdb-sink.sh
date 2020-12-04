#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ -z "$KSQLDB" ]
then
     ${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"
else
     ${DIR}/../../ksqldb/environment/start.sh "${PWD}/docker-compose.plaintext.yml"
fi


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer \
     --broker-list broker:9092 \
     --property schema.registry.url=http://schema-registry:8081 \
     --topic orders \
     --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"measurement","type":"string"},{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"measurement": "orders", "id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

docker exec -i connect kafka-avro-console-consumer \
     --bootstrap-server broker:9092 \
     --property schema.registry.url=http://schema-registry:8081 \
     --topic orders \
     --from-beginning \
     --max-messages=1

log "Creating orders InfluxDB sink connector"
curl -s -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.influxdb.InfluxDBSinkConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "topics": "orders"
          }' \
     http://localhost:8083/connectors/influxdb-sink/config | jq .

sleep 10

log "Verify that order is in InfluxDB"
docker exec influxdb influx -database orders -execute 'select * from orders'
