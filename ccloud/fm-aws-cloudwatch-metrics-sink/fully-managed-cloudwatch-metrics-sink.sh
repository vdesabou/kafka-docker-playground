#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

handle_aws_credentials

bootstrap_ccloud_environment "aws" "$AWS_REGION"

set +e
playground topic delete --topic cloudwatch-metrics-topic
sleep 3
playground topic create --topic cloudwatch-metrics-topic --nb-partitions 1
set -e

TIMESTAMP=`date +%s000`
log "Sending messages to topic cloudwatch-metrics-topic"
playground topic produce --topic cloudwatch-metrics-topic --nb-messages 1 --key "key1" --forced-value "{\"name\" : \"test_meter\",\"type\" : \"meter\", \"timestamp\" : $TIMESTAMP, \"dimensions\" : {\"dimensions1\" : \"InstanceID\",\"dimensions2\" : \"i-aaba32d4\"},\"values\" : {\"count\" : 32423.0,\"oneMinuteRate\" : 342342.2,\"fiveMinuteRate\" : 34234.2,\"fifteenMinuteRate\" : 2123123.1,\"meanRate\" : 2312312.1}}" << 'EOF'
{
  "name": "myMetric",
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
            "name": "dimensions1",
            "type": "string"
          },
          {
            "name": "dimensions2",
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
            "name": "count",
            "type": "double"
          },
          {
            "name": "oneMinuteRate",
            "type": "double"
          },
          {
            "name": "fiveMinuteRate",
            "type": "double"
          },
          {
            "name": "fifteenMinuteRate",
            "type": "double"
          },
          {
            "name": "meanRate",
            "type": "double"
          }
        ]
      }
    }
  ]
}
EOF

connector_name="CloudWatchMetricsSink_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating AWS CloudWatch Logs Source connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "CloudWatchMetricsSink",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "topics": "cloudwatch-metrics-topic",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "input.data.format": "AVRO",
    "aws.cloudwatch.metrics.url": "https://monitoring.$AWS_REGION.amazonaws.com",
    "aws.cloudwatch.metrics.namespace": "service-namespace",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "View the metrics being produced to Amazon CloudWatch"
aws cloudwatch list-metrics --namespace service-namespace --region $AWS_REGION > /tmp/result.log  2>&1
cat /tmp/result.log
grep "test_meter_fifteenMinuteRate" /tmp/result.log

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name