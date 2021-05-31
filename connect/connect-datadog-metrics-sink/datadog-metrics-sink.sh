#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

DD_API_KEY=${DD_API_KEY:-$1}
DD_APP_KEY=${DD_APP_KEY:-$2}

if [ -z "$DD_API_KEY" ]
then
     logerror "DD_API_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if [ -z "$DD_APP_KEY" ]
then
     logerror "DD_APP_KEY is not set. Export it as environment variable or pass it as argument"
     exit 1
fi

if test -z "$(docker images -q dogshell:latest)"
then
     log "Building dogshell docker image.."
     OLDDIR=$PWD
     cd ${DIR}/docker-dogshell
     docker build -t dogshell:latest .
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic datadog-metrics-topic"
TIMESTAMP=`date +%s`
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic datadog-metrics-topic --property value.schema='{"name": "metric","type": "record","fields": [{"name": "name","type": "string"},{"name": "type","type": "string"},{"name": "timestamp","type": "long"}, {"name": "dimensions", "type": {"name": "dimensions", "type": "record", "fields": [{"name": "host", "type":"string"}, {"name":"interval", "type":"int"}, {"name": "tag1", "type":"string"}]}},{"name": "values","type": {"name": "values","type": "record","fields": [{"name":"doubleValue", "type": "double"}]}}]}' << EOF
{"name":"perf.metric", "type":"rate","timestamp": $TIMESTAMP, "dimensions": {"host": "metric.host1", "interval": 1, "tag1": "testing-data"},"values": {"doubleValue": 5.639623848362502}}
EOF

log "Creating Datadog metrics sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.datadog.metrics.DatadogMetricsSinkConnector",
               "tasks.max": "1",
               "key.converter":"org.apache.kafka.connect.storage.StringConverter",
               "value.converter":"io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url":"http://schema-registry:8081",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor":1,
               "datadog.api.key": "'"$DD_API_KEY"'",
               "datadog.domain": "COM",
               "reporter.bootstrap.servers": "broker:9092",
               "reporter.error.topic.name": "error-responses",
               "reporter.error.topic.replication.factor": 1,
               "reporter.result.topic.name": "success-responses",
               "reporter.result.topic.replication.factor": 1,
               "behavior.on.error": "fail",
               "topics": "datadog-metrics-topic"
          }' \
     http://localhost:8083/connectors/datadog-metrics-sink/config | jq .

sleep 20

log "Make sure perf.metric is present in Datadog"
docker run -e DOGSHELL_API_KEY=$DD_API_KEY -e DOGSHELL_APP_KEY=$DD_APP_KEY dogshell:latest search query perf.metric > /tmp/result.log  2>&1
cat /tmp/result.log
grep "perf.metric" /tmp/result.log
