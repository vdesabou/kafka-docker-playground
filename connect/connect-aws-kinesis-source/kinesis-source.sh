#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.3.14"
then
    logwarn "connector version >= 1.3.15 do not support CP versions < 6.0.0"
    exit 111
fi

if [ ! -z "$TAG_BASE" ] && version_gt $TAG_BASE "7.9.99" && [ ! -z "$CONNECTOR_TAG" ] && ! version_gt $CONNECTOR_TAG "1.2.99"
then
     logwarn "minimal supported connector version is 1.3.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

KINESIS_STREAM_NAME=pg${USER}${TAG}
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME//[-.]/}

set +e
log "Delete the stream"
aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
set -e

sleep 5

log "Create a Kinesis stream $KINESIS_STREAM_NAME"
aws kinesis create-stream --stream-name $KINESIS_STREAM_NAME --shard-count 1 --region $AWS_REGION --tags "cflt_managed_by=user,cflt_managed_id=$USER"

function cleanup_cloud_resources {
    set +e
    log "Delete the Kinesis stream"
    check_if_continue
    aws kinesis delete-stream --stream-name $KINESIS_STREAM_NAME --region $AWS_REGION
}
trap cleanup_cloud_resources EXIT

log "Sleep 60 seconds to let the Kinesis stream being fully started"
sleep 60

log "Insert records in Kinesis stream".
aws kinesis put-record --stream-name $KINESIS_STREAM_NAME --partition-key 123 --data test-message-1 --region $AWS_REGION

log "Creating Kinesis Source connector"
playground connector create-or-update --connector kinesis-source  << EOF
{
    "connector.class":"io.confluent.connect.kinesis.KinesisSourceConnector",
    "tasks.max": "1",
    "kafka.topic": "kinesis_topic",
    "kinesis.stream": "$KINESIS_STREAM_NAME",
    "kinesis.region": "$AWS_REGION",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

log "Verify we have received the data in kinesis_topic topic"
playground topic consume --topic kinesis_topic --min-expected-messages 1 --timeout 60