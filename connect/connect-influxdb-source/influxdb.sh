#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating testdb database and inserting into coin table"
docker exec -i influxdb bash -c "influx -execute 'create database testdb'"
docker exec -i influxdb bash -c "influx -execute 'INSERT coin,id=1 value=100' -database testdb"

log "Verifying data in testdb"
docker exec -i influxdb bash -c "influx -execute 'SELECT * from coin' -database testdb"

log "Creating InfluxDB source connector"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.influxdb.source.InfluxdbSourceConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "influxdb.db": "testdb",
                    "mode": "timestamp",
                    "topic.prefix": "influx_",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }' \
     http://localhost:8083/connectors/influxdb-source/config | jq_docker_cli .

sleep 10

log "Verifying topic influx_testdb"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server localhost:9092 --topic influx_testdb --from-beginning --max-messages 1


