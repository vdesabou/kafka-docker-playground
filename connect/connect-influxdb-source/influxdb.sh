#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo "Creating mydb database"
curl -i -XPOST 'http://localhost:8086/query' --data-urlencode "q=CREATE DATABASE mydb"
echo "Inserting data in database"
curl -i -XPOST 'http://localhost:8086/write?db=mydb' --data-binary 'cpu_load_short,host=server01,region=us-west value=0.64 1434055562000000000'
echo "Verifying data in mydb"
curl -G 'http://localhost:8086/query?pretty=true' --data-urlencode "db=mydb" --data-urlencode "q=SELECT \"value\" FROM \"cpu_load_short\" WHERE \"region\"='us-west'"

echo "Creating InfluxDB source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.influxdb.source.InfluxdbSourceConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "influxdb.db": "mydb",
                    "mode": "timestamp",
                    "topic.prefix": "influx_",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/influxdb-source/config | jq .

sleep 10

echo "Verifying topic influx_cpu_load_short"
docker exec broker kafka-console-consumer --bootstrap-server localhost:9092 --topic influx_cpu_load_short --from-beginning --max-messages 1


