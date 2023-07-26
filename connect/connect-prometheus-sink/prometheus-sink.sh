#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Creating Prometheus sink connector"
playground connector create-or-update --connector prometheus-sink << EOF
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
playground topic produce -t test-topic --nb-messages 6 --forced-value "{\"name\":\"kafka_gaugeMetric%g\", \"type\":\"gauge\",\"timestamp\": $NOW,\"values\": {\"doubleValue\": 5.639623848362502}}" << 'EOF'
{
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "type",
      "type": "string"
    },
    {
      "name": "timestamp",
      "type": "long"
    },
    {
      "name": "values",
      "type": {
        "fields": [
          {
            "name": "doubleValue",
            "type": "double"
          }
        ],
        "name": "values",
        "type": "record"
      }
    }
  ],
  "name": "metric",
  "type": "record"
}
EOF

sleep 6

log "Verify data is in Prometheus"
curl 'http://localhost:19090/api/v1/query?query=kafka_gaugeMetric1' > /tmp/result.log  2>&1
cat /tmp/result.log
grep "kafka_gaugeMetric1" /tmp/result.log

# FIXTHIS: if  we execute same command again, it will show no results....