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

bootstrap_ccloud_environment

set +e
playground topic delete --topic datadog-metrics-topic
sleep 3
playground topic create --topic datadog-metrics-topic --nb-partitions 1
set -e


connector_name="DatadogMetricsSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
  "connector.class": "DatadogMetricsSink",
  "name": "$connector_name",
  "kafka.auth.mode": "KAFKA_API_KEY",
  "kafka.api.key": "$CLOUD_KEY",
  "kafka.api.secret": "$CLOUD_SECRET",
  "topics": "datadog-metrics-topic",
  "datadog.api.key": "$DD_API_KEY",
  "datadog.domain": "COM",
  "input.data.format" : "AVRO",
  "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Sending messages to topic datadog-metrics-topic"
TIMESTAMP=`date +%s`
playground topic produce -t datadog-metrics-topic --nb-messages 1 --forced-value="{\"name\":\"perf.metric\", \"type\":\"rate\",\"timestamp\": $TIMESTAMP, \"dimensions\": {\"host\": \"metric.host1\", \"interval\": 1, \"tag1\": \"testing-data\"},\"values\": {\"doubleValue\": 5.639623848362502}}" << 'EOF'
{
  "name": "metric",
  "type": "record",
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
      "name": "dimensions",
      "type": {
        "name": "dimensions",
        "type": "record",
        "fields": [
          {
            "name": "host",
            "type": "string"
          },
          {
            "name": "interval",
            "type": "int"
          },
          {
            "name": "tag1",
            "type": "string"
          }
        ]
      }
    },
    {
      "name": "values",
      "type": {
        "name": "values",
        "type": "record",
        "fields": [
          {
            "name": "doubleValue",
            "type": "double"
          }
        ]
      }
    }
  ]
}
EOF

sleep 20

connectorId=$(get_ccloud_connector_lcc $connector_name)

log "Verifying topic success-$connectorId"
playground topic consume --topic success-$connectorId --min-expected-messages 1 --timeout 60

playground topic consume --topic error-$connectorId --min-expected-messages 0 --timeout 60

log "Make sure perf.metric is present in Datadog"
docker run -e DOGSHELL_API_KEY=$DD_API_KEY -e DOGSHELL_APP_KEY=$DD_APP_KEY dogshell:latest search query perf.metric > /tmp/result.log  2>&1
cat /tmp/result.log
grep "perf.metric" /tmp/result.log
