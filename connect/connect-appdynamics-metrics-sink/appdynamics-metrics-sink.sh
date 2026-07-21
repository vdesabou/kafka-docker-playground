#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

# A real AppDynamics machine agent requires an AppDynamics account + Controller
# before it opens its HTTP metric listener, so it cannot run self-contained in
# CI. Instead we run a small mock of the listener (docker-appdynamics-metrics/
# mock-machine-agent.py) that accepts POST /api/v1/metrics and returns HTTP 204,
# which is exactly the contract the connector (AppDClient) relies on.

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic appdynamics-metrics-topic"
playground topic produce -t appdynamics-metrics-topic << 'EOF'
{
  "fields": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "dimensions",
      "type": {
        "fields": [
          {
            "name": "aggregatorType",
            "type": {
              "type": "enum",
              "name": "aggregatorTypeEnum",
              "symbols": ["SUM", "AVERAGE", "OBSERVATION"]
            }
          }
        ],
        "name": "dimensions",
        "type": "record"
      }
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

log "Creating AppDynamics Metrics sink connector"
playground connector create-or-update --connector appdynamics-metrics-sink  << EOF
{
    "connector.class": "io.confluent.connect.appdynamics.metrics.AppDynamicsMetricsSinkConnector",
    "tasks.max": "1",
    "topics": "appdynamics-metrics-topic",
    "machine.agent.host": "http://appdynamics-metrics",
    "machine.agent.port": "8293",
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url":"http://schema-registry:8081",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url":"http://schema-registry:8081",
    "reporter.bootstrap.servers": "broker:9092",
    "reporter.error.topic.replication.factor": 1,
    "reporter.result.topic.replication.factor": 1,
    "behavior.on.error": "fail",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

sleep 5


log "Verify the connector delivered metrics to the (mock) machine agent HTTP listener"
# The mock logs every POST it receives. A metrics payload contains "metricName",
# which proves the connector extracted the records and delivered them (getting
# HTTP 204); the periodic empty "[]" heartbeat posts do not contain "metricName".
playground container logs --container appdynamics-metrics --wait-for-log "metricName" --max-wait 60
