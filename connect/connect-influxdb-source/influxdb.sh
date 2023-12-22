#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

playground start-environment --environment plaintext --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating testdb database and inserting into coin table"
docker exec -i influxdb bash -c "influx -execute 'create database testdb'"
docker exec -i influxdb bash -c "influx -execute 'INSERT coin,id=1 value=100' -database testdb"

log "Verifying data in testdb"
docker exec -i influxdb bash -c "influx -execute 'SELECT * from coin' -database testdb"

log "Creating InfluxDB source connector"
playground connector create-or-update --connector influxdb-source << EOF
{
               "connector.class": "io.confluent.influxdb.source.InfluxdbSourceConnector",
                    "tasks.max": "1",
                    "influxdb.url": "http://influxdb:8086",
                    "influxdb.db": "testdb",
                    "mode": "timestamp",
                    "topic.prefix": "influx_",
                    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
                    "value.converter.schemas.enable": "false"
          }
EOF

sleep 10

log "Verifying topic influx_testdb"
playground topic consume --topic influx_testdb --min-expected-messages 1 --timeout 60


