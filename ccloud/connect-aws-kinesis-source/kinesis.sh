#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.3.14"
then
    logwarn "WARN: connector version >= 1.3.15 do not support CP versions < 6.0.0"
    exit 111
fi

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

playground start-environment --environment ccloud --docker-compose-override-file "${PWD}/docker-compose.yml"

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi

KINESIS_STREAM_NAME=kafka_docker_pg_kinesis$TAG
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME//[-.]/}
KINESIS_TOPIC=$KINESIS_STREAM_NAME

set +e
playground topic delete --topic $KINESIS_TOPIC
set -e

if ! version_gt $TAG_BASE "5.9.9"; then
     # note: for 6.x CONNECT_TOPIC_CREATION_ENABLE=true
     log "Creating topic in Confluent Cloud (auto.create.topics.enable=false)"
     set +e
     playground topic create --topic $KINESIS_TOPIC
     set -e
fi

set +e
log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
set -e

sleep 5

log "Create a Kinesis stream $KINESIS_STREAM_NAME"
aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1 --region $AWS_REGION

log "Sleep 60 seconds to let the Kinesis stream being fully started"
sleep 60

log "Insert records in Kinesis stream"
# The example shows that a record containing partition key 123 and data "test-message-1" is inserted into kafka_docker_playground.
aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1 --region $AWS_REGION



log "Creating Kinesis Source connector"
playground connector create-or-update --connector kinesis-source  << EOF
{
    "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
    "tasks.max": "1",
    "kafka.topic": "$KINESIS_TOPIC",
    "kinesis.stream": "$KINESIS_STREAM_NAME",
    "kinesis.region": "$AWS_REGION",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY",
    "confluent.license": "",
    "topic.creation.default.replication.factor": "-1",
    "topic.creation.default.partitions": "-1",
    "confluent.topic.bootstrap.servers": "\${file:/data:bootstrap.servers}",
    "confluent.topic.sasl.jaas.config" : "org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${file:/data:sasl.username}\" password=\"\${file:/data:sasl.password}\";",
    "confluent.topic.security.protocol" : "SASL_SSL",
    "confluent.topic.sasl.mechanism" : "PLAIN"
}
EOF

sleep 60

log "Verify we have received the data in $KINESIS_TOPIC topic"
playground topic consume --topic $KINESIS_TOPIC --min-expected-messages 1 --timeout 60

log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION