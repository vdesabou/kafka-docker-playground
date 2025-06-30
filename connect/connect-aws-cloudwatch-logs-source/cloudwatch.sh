#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "1.3.2"
then
     logwarn "minimal supported connector version is 1.3.3 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

handle_aws_credentials

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

LOG_GROUP=pg${USER}lg${TAG}
LOG_GROUP=${LOG_GROUP//[-.]/}
LOG_STREAM=pg${USER}ls${TAG}
LOG_STREAM=${LOG_STREAM//[-.]/}

# cleanup
set +e
aws logs delete-log-group --log-group-name $LOG_GROUP
set -e

log "Create a log group in AWS CloudWatch Logs."
aws logs create-log-group --log-group-name $LOG_GROUP

log "Create a log stream in AWS CloudWatch Logs."
aws logs create-log-stream --log-group-name $LOG_GROUP --log-stream $LOG_STREAM

function cleanup_cloud_resources {
    set +e
    log "Do you want to delete the log group $LOG_GROUP ?"
    check_if_continue
    aws logs delete-log-stream --log-group-name "$LOG_GROUP" --log-stream-name "$LOG_STREAM"
    aws logs delete-log-group --log-group-name "$LOG_GROUP"
}
trap cleanup_cloud_resources EXIT

log "Insert Records into your log stream."
# If this is the first time inserting logs into a new log stream, then no sequence token is needed.
# However, after the first put, there will be a sequence token returned that will be needed as a parameter in the next put.
aws logs put-log-events --log-group-name $LOG_GROUP --log-stream $LOG_STREAM --log-events timestamp=`date +%s000`,message="This is a log #0"

log "Injecting more messages"
for i in $(seq 1 10)
do
     token=$(aws logs describe-log-streams --log-group-name $LOG_GROUP | jq -r .logStreams[0].uploadSequenceToken)
     aws logs put-log-events --log-group-name $LOG_GROUP --log-stream $LOG_STREAM --log-events timestamp=`date +%s000`,message="This is a log #${i}" --sequence-token ${token}
done


CLOUDWATCH_LOGS_URL="https://logs.$AWS_REGION.amazonaws.com"

log "Creating AWS CloudWatch Logs Source connector"
playground connector create-or-update --connector aws-cloudwatch-logs-source  << EOF
{
    "connector.class": "io.confluent.connect.aws.cloudwatch.AwsCloudWatchSourceConnector",
    "tasks.max": "1",
    "aws.cloudwatch.logs.url": "$CLOUDWATCH_LOGS_URL",
    "aws.cloudwatch.log.group": "$LOG_GROUP",
    "aws.cloudwatch.log.streams": "$LOG_STREAM",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1"
}
EOF

sleep 5

log "Verify we have received the data in $LOG_GROUP.$LOG_STREAM topic"
playground topic consume --topic $LOG_GROUP.$LOG_STREAM --min-expected-messages 11 --timeout 60