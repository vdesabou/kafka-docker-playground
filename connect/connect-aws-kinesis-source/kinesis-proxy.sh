#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ ! -f $HOME/.aws/credentials ]
then
     logerror "ERROR: $HOME/.aws/credentials is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-proxy.yml"

KINESIS_STREAM_NAME=my_kinesis_stream$TAG
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME//[-.]/}

set +e
log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME
set -e

sleep 5

log "Create a Kinesis stream $KINESIS_STREAM_NAME"
aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1

log "Sleep 60 seconds to let the Kinesis stream being fully started"
sleep 60

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into my_kinesis_stream.
aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1

AWS_REGION=$(aws configure get region | tr '\r' '\n')

log "Creating Kinesis Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.stream": "'"$KINESIS_STREAM_NAME"'",
               "kinesis.region": "'"$AWS_REGION"'",
               "kinesis.proxy.url": "https://nginx_proxy:8888",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source/config | jq .

log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME