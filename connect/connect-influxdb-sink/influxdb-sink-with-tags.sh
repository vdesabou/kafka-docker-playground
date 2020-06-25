#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic product"
docker exec -i connect kafka-avro-console-producer \
     --broker-list broker:9092 \
     --property schema.registry.url=http://schema-registry:8081 \
     --topic product \
     --property value.schema='{"name": "myrecord","type": "record","fields": [{"name":"id","type":"int"}, {"name": "product","type": "string"}, {"name": "quantity","type": "int"},{"name": "price","type": "float"}, {"name": "tags","type": {"name": "tags","type": "map","values": "string"}}]}'  << EOF
{"id": 1, "product": "pencil", "quantity": 100, "price": 50, "tags": {"DEVICE": "living", "location": "home"}}
EOF

docker exec -i connect kafka-avro-console-consumer \
     --bootstrap-server broker:9092 \
     --property schema.registry.url=http://schema-registry:8081 \
     --topic product \
     --from-beginning \
     --max-messages=1

log "Creating product InfluxDB sink connector using SMT for fun"
docker exec connect \
     curl -s -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.influxdb.InfluxDBSinkConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "topics": "product",
                    "transforms": "InsertField,RenameField",
                    "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
                    "transforms.InsertField.static.field": "measurement",
                    "transforms.InsertField.static.value": "product",
                    "transforms.RenameField.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
                    "transforms.RenameField.renames": "product:name"                   
               }
          }' \
     http://localhost:8083/connectors/influxdb-sink/config | jq .

sleep 10

log "Verify product data is in InfluxDB with its tags"
docker exec influxdb influx -database product -execute 'select * from product'
