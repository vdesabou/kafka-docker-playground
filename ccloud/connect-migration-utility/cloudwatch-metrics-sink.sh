#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if connect_cp_version_greater_than_8 && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "2.0.3"
then
     logwarn "minimal supported connector version is 2.0.4 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

handle_aws_credentials

log "forcing PLAYGROUND_ENVIRONMENT to ccloud"
PLAYGROUND_ENVIRONMENT="ccloud"
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

TIMESTAMP=$(date +%s000)
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

CLOUDWATCH_METRICS_URL="https://monitoring.$AWS_REGION.amazonaws.com"

connector_name="OnPremCloudWatchMetricsSink_$USER"

log "Creating AWS CloudWatch metrics Sink connector"
playground connector create-or-update --connector $connector_name  << EOF
{
    "tasks.max": "1",
    "topics": "cloudwatch-metrics-topic",
    "connector.class": "io.confluent.connect.aws.cloudwatch.metrics.AwsCloudWatchMetricsSinkConnector",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",
    "aws.cloudwatch.metrics.url": "$CLOUDWATCH_METRICS_URL",
    "aws.cloudwatch.metrics.namespace": "service-namespace",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "behavior.on.malformed.metric": "FAIL",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

sleep 10

log "View the metrics being produced to Amazon CloudWatch"
aws cloudwatch list-metrics --namespace service-namespace --region $AWS_REGION > /tmp/result.log  2>&1
cat /tmp/result.log
grep "test_meter_fifteenMinuteRate" /tmp/result.log

# To verify that the connector is working with ccloud environment
playground connector connect-migration-utility discovery

# 16:32:09 ℹ️ 📝 Summary of the discovery process:
# ================================================================================
#  Overall Summary
# ================================================================================
# Number of Connector clusters scanned: 1
# Total Connector configurations scanned: 1
# Total Connectors that can be successfully migrated: 1
# Total Connectors that have errors in migration: 0

# ================================================================================
# Summary By Connector Type
# ================================================================================
# ✅ Connector types (successful across all clusters):
#   - CloudWatchMetricsSink: 1

# ❌ Connector types (with errors across all clusters):

# ================================================================================
#  Per-Cluster Summary (sorted by successful configurations for migration)
# ================================================================================

# Cluster Details: .
#   Total Connector configurations scanned: 1
#   Total Connectors that can be successfully migrated: 1
#     ✅ Connector types (successful):
#       - CloudWatchMetricsSink: 1
#   Total Connectors that have errors in migration: 0

# ================================================================================
#  Connector Mapping Errors (all unsuccessful configs)
# ================================================================================
# 16:32:09 ℹ️ 📁 Found        1 connector configuration(s) that can be migrated to fully managed:
# /Users/vsaboulin/Documents/github/kafka-docker-playground/connect-migration-utility-discovery-output/discovered_configs/successful_configs/fm_configs
# └── fm_config_aws-cloudwatch-metrics-sink.json

# 0 directories, 1 file

# 16:32:09 ℹ️ 📄 fm_config_aws-cloudwatch-metrics-sink.json
# {
#   "name": "aws-cloudwatch-metrics-sink",
#   "config": {
#     "connector.class": "CloudWatchMetricsSink",
#     "name": "aws-cloudwatch-metrics-sink",
#     "tasks.max": "1",
#     "topics": "cloudwatch-metrics-topic",
#     "aws.secret.access.key": "xxxx",
#     "input.data.format": "AVRO",
#     "aws.cloudwatch.metrics.namespace": "service-namespace",
#     "aws.access.key.id": "xxxx",
#     "behavior.on.malformed.metric": "FAIL"
#   }
# }

playground connector connect-migration-utility migrate --migration-mode create_latest_offset --sensitive-property "aws.access.key.id=$AWS_ACCESS_KEY_ID" --sensitive-property "aws.secret.access.key=$AWS_SECRET_ACCESS_KEY"


# 16:36:00 ℹ️ 🧩 Displaying status for 🌤️🤖fully managed connector aws-cloudwatch-metrics-sink (lcc-526mn2)
# Name                           Status       Tasks                                                        Stack Trace                                       
# -------------------------------------------------------------------------------------------------------------
# aws-cloudwatch-metrics-sink    ✅ RUNNING  0:🟢 RUNNING                 -                                                 
# -------------------------------------------------------------------------------------------------------------


TIMESTAMP=$(date +%s000)
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


playground connector show-lag --connector $connector_name

# 🕙[ 16:37:29 ] ➜  playground connector show-lag
# 16:38:04 ℹ️ 🏁 consumer lag for 🌤️🤖fully managed connector aws-cloudwatch-metrics-sink (lcc-526mn2) is 0 ! took: 0min 5sec
# topic: cloudwatch-metrics-topic partition: 0   current-offset: 2          end-offset: 2          lag: 0          [🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹🔹] 100% 🏁


log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name