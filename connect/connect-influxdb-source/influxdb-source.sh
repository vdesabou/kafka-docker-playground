#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "1.1.99"
then
     logwarn "minimal supported connector version is 1.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating testdb database and inserting into coin table"
docker exec -i influxdb bash -c "influx -execute 'create database testdb'"
docker exec -i influxdb bash -c "influx -execute 'INSERT coin,id=1 value=100' -database testdb"

log "Verifying data in testdb"
docker exec -i influxdb bash -c "influx -execute 'SELECT * from coin' -database testdb"

log "Creating InfluxDB source connector"
playground connector create-or-update --connector influxdb-source  << EOF
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


