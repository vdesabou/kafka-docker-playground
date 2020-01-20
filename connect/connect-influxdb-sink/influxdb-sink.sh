#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Sending messages to topic orders"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"measurement","type":"string"},{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"measurement": "orders", "id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF


log "Creating InfluxDB sink connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.influxdb.InfluxDBSinkConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "topics": "orders"
          }' \
     http://localhost:8083/connectors/influxdb-sink/config | jq_docker_cli .

sleep 10

log "Verify data is in InfluxDB"
curl -G 'http://localhost:8086/query?pretty=true' --data-urlencode "db=orders" --data-urlencode "q=SELECT \"price\" FROM \"orders\""
