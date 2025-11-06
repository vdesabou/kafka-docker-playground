#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.0.3"
then
     logwarn "minimal supported connector version is 2.0.4 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.1.html#supported-connector-versions-in-cp-8-1"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating Prometheus sink connector"
playground connector create-or-update --connector prometheus-sink  << EOF
{
  "connector.class": "io.confluent.connect.prometheus.PrometheusMetricsSinkConnector",
  "tasks.max": "1",
  "confluent.topic.bootstrap.servers":"broker:9092",
  "confluent.topic.replication.factor": "1",
  "prometheus.listener.url": "http://connect:8889/metrics",
  "key.converter": "io.confluent.connect.avro.AvroConverter",
  "key.converter.schema.registry.url":"http://schema-registry:8081",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url":"http://schema-registry:8081",
  "reporter.bootstrap.servers": "broker:9092",
  "reporter.error.topic.replication.factor": 1,
  "reporter.result.topic.replication.factor": 1,
  "behavior.on.error": "LOG",
  "topics": "test-topic"
}
EOF

NOW=$(date +%s)
log "Sending messages to topic test-topic"
docker exec -i -e NOW=$NOW connect kafka-avro-console-producer --bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic test-topic --property value.schema='{"name": "metric","type": "record","fields": [{"name": "name","type": "string"},{"name": "type","type": "string"},{"name": "timestamp","type": "long"},{"name": "values","type": {"name": "values","type": "record","fields": [{"name":"doubleValue", "type": "double"}]}}]}' << EOF
{"name":"kafka_gaugeMetric1", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric2", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric3", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric4", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric5", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
{"name":"kafka_gaugeMetric6", "type":"gauge","timestamp": $NOW,"values": {"doubleValue": 5.639623848362502}}
EOF

sleep 6

log "Verify data is in Prometheus"
curl 'http://localhost:19090/api/v1/query?query=kafka_gaugeMetric1' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "kafka_gaugeMetric1" /tmp/result.log

# if  we execute same command again, it will show no results....

# The Problem:
# Prometheus sink connector exposes metrics at http://connect:8889/metrics
# When Prometheus scrapes this endpoint (every 5 seconds), it consumes/deletes the metrics from the connector's buffer
# Your manual curl query works the first time, but subsequent queries return empty because Prometheus already consumed the data

# Why This Happens:
# This is the intended behavior of the Prometheus sink connector - it acts as a buffer that exposes metrics until they're scraped, then clears them. This prevents memory buildup and follows Prometheus pull model best practices.