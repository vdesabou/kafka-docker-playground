#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

echo -e "\033[0;33mCreating mydb database\033[0m"
curl -i -XPOST 'http://localhost:8086/query' --data-urlencode "q=CREATE DATABASE mydb"
echo -e "\033[0;33mInserting data in database\033[0m"
curl -i -XPOST 'http://localhost:8086/write?db=mydb' --data-binary 'cpu_load_short,host=server01,region=us-west value=0.64 1434055562000000000'
echo -e "\033[0;33mVerifying data in mydb\033[0m"
curl -G 'http://localhost:8086/query?pretty=true' --data-urlencode "db=mydb" --data-urlencode "q=SELECT \"value\" FROM \"cpu_load_short\" WHERE \"region\"='us-west'"

echo -e "\033[0;33mCreating InfluxDB source connector\033[0m"
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

echo -e "\033[0;33mVerifying topic influx_cpu_load_short\033[0m"
docker exec broker kafka-console-consumer --bootstrap-server localhost:9092 --topic influx_cpu_load_short --from-beginning --max-messages 1


