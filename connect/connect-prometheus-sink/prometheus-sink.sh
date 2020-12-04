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

NOW=$(date +%s)
log "Sending messages to topic test-topic"
docker exec -i -e NOW=$NOW connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-topic --property value.schema='{"name": "metric","type": "record","fields": [{"name": "name","type": "string"},{"name": "type","type": "string"},{"name": "timestamp","type": "long"},{"name": "values","type": {"name": "values","type": "record","fields": [{"name":"doubleValue", "type": "double"}]}}]}' << EOF
{"name":"kafka_gaugeMetric1", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric2", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric3", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
EOF

log "Creating Prometheus sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.prometheus.PrometheusMetricsSinkConnector",
               "tasks.max": "1",
               "confluent.topic.bootstrap.servers":"broker:9092",
               "confluent.topic.replication.factor": "1",
               "prometheus.scrape.url": "http://connect:8889/metrics",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url":"http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "key.converter.schemas.enable": "true",
               "value.converter.schemas.enable": "true",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.replication.factor": 1,
               "behavior.on.error": "LOG",
               "topics": "test-topic"
          }' \
     http://localhost:8083/connectors/prometheus-sink/config | jq .

sleep 10

log "Verify data is in Prometheus"
curl 'http://localhost:9090/api/v1/query?query=kafka_gaugeMetric1'
