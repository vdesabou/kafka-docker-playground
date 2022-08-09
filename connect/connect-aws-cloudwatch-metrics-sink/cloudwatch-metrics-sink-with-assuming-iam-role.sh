#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

export AWS_CREDENTIALS_FILE_NAME=credentials-with-assuming-iam-role
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
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

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.with-assuming-iam-role.yml"

TIMESTAMP=`date +%s000`
log "Sending messages to topic cloudwatch-metrics-topic"
docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic cloudwatch-metrics-topic --property parse.key=true --property key.separator=, --property key.schema='{"type":"string"}' --property value.schema='{"name": "myMetric","type": "record","fields": [{"name": "name","type": "string"},{"name": "type","type": "string"},{"name": "timestamp","type": "long"},{"name": "dimensions","type": {"name": "dimensions","type": "record","fields": [{"name": "dimensions1","type": "string"},{"name": "dimensions2","type": "string"}]}},{"name": "values","type": {"name": "values","type": "record","fields": [{"name":"count", "type": "double"},{"name":"oneMinuteRate", "type": "double"},{"name":"fiveMinuteRate", "type": "double"},{"name":"fifteenMinuteRate", "type": "double"},{"name":"meanRate", "type": "double"}]}}]}' << EOF
"key1", {"name" : "test_meter","type" : "meter", "timestamp" : $TIMESTAMP, "dimensions" : {"dimensions1" : "InstanceID","dimensions2" : "i-aaba32d4"},"values" : {"count" : 32423.0,"oneMinuteRate" : 342342.2,"fiveMinuteRate" : 34234.2,"fifteenMinuteRate" : 2123123.1,"meanRate" : 2312312.1}}
EOF


CLOUDWATCH_METRICS_URL="https://monitoring.$AWS_REGION.amazonaws.com"

log "Creating AWS CloudWatch metrics Sink connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "topics": "cloudwatch-metrics-topic",
               "connector.class": "io.confluent.connect.aws.cloudwatch.metrics.AwsCloudWatchMetricsSinkConnector",
               "key.converter": "io.confluent.connect.avro.AvroConverter",
               "key.converter.schema.registry.url": "http://schema-registry:8081",
               "value.converter": "io.confluent.connect.avro.AvroConverter",
               "value.converter.schema.registry.url": "http://schema-registry:8081",
               "aws.cloudwatch.metrics.url": "'"$CLOUDWATCH_METRICS_URL"'",
               "aws.cloudwatch.metrics.namespace": "service-namespace",
               "behavior.on.malformed.metric": "FAIL",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-cloudwatch-metrics-sink/config | jq .

sleep 10

log "View the metrics being produced to Amazon CloudWatch"
aws cloudwatch list-metrics --namespace service-namespace > /tmp/result.log  2>&1
cat /tmp/result.log
grep "test_meter_fifteenMinuteRate" /tmp/result.log
