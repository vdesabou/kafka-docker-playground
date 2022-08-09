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

KINESIS_STREAM_NAME=kafka_docker_playground$TAG
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
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into kafka_docker_playground.
aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1



log "Creating Kinesis Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
               "tasks.max": "1",
               "kafka.topic": "kinesis_topic",
               "kinesis.stream": "'"$KINESIS_STREAM_NAME"'",
               "kinesis.region": "'"$AWS_REGION"'",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/kinesis-source/config | jq .

log "Verify we have received the data in kinesis_topic topic"
timeout 60 docker exec broker kafka-console-consumer --bootstrap-server broker:9092 --topic kinesis_topic --from-beginning --max-messages 1

log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME