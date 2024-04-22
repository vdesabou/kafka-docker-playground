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

bootstrap_ccloud_environment

set +e
playground topic delete --topic kinesis_topic
sleep 3
playground topic create --topic kinesis_topic --nb-partitions 1
set -e

KINESIS_STREAM_NAME=pg${USER}${TAG}
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME//[-.]/}

set +e
log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
set -e

sleep 5

log "Create a Kinesis stream $KINESIS_STREAM_NAME"
aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1 --region $AWS_REGION

function cleanup_cloud_resources {
    log "Delete the Kinesis stream"
    check_if_continue
    aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
}
trap cleanup_cloud_resources EXIT

log "Sleep 60 seconds to let the Kinesis stream being fully started"
sleep 60

log "Insert records in Kinesis stream".
aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1 --region $AWS_REGION


connector_name="KinesisSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e

log "Creating fully managed connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "KinesisSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "kafka.topic": "kinesis_topic",
    "kinesis.stream": "$KINESIS_STREAM_NAME",
    "kinesis.region": "$AWS_REGION",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

log "Verify we have received the data in kinesis_topic topic"
playground topic consume --topic kinesis_topic --min-expected-messages 1 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue
playground connector delete --connector $connector_name