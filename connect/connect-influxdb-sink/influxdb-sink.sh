#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo "Sending messages to topic orders"
docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic orders --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"measurement","type":"string"},{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"measurement": "orders", "id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF


echo "Creating InfluxDB sink connector"
docker exec connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "InfluxDBSinkConnector",
               "config": {
                    "connector.class": "io.confluent.influxdb.InfluxDBSinkConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "topics": "orders"
          }}' \
     http://localhost:8083/connectors | jq .

sleep 10

echo "Verify data is in InfluxDB"
curl -G 'http://localhost:8086/query?pretty=true' --data-urlencode "db=orders" --data-urlencode "q=SELECT \"price\" FROM \"orders\""
