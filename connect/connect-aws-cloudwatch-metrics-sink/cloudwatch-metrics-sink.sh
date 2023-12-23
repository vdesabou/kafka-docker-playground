#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
then
     logerror "ERROR: either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
     exit 1
else
    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
    then
        log "💭 Using environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
    else
        if [ -f $HOME/.aws/credentials ]
        then
            logwarn "💭 AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set based on $HOME/.aws/credentials"
            export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' )
            export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials | head -1 | awk -F'=' '{print $2;}' ) 
        fi
    fi
    if [ -z "$AWS_REGION" ]
    then
        AWS_REGION=$(aws configure get region | tr '\r' '\n')
        if [ "$AWS_REGION" == "" ]
        then
            logerror "ERROR: either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
            exit 1
        fi
    fi
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

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

CLOUDWATCH_METRICS_URL="https://monitoring.$AWS_REGION.amazonaws.com"

log "Creating AWS CloudWatch metrics Sink connector"
playground connector create-or-update --connector aws-cloudwatch-metrics-sink --environment "${PLAYGROUND_ENVIRONMENT}" << EOF
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