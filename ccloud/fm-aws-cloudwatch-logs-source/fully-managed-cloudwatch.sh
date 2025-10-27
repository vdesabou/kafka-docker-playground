#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

handle_aws_credentials

bootstrap_ccloud_environment "aws" "$AWS_REGION"

LOG_GROUP=pgfm${USER}lg${GITHUB_RUN_NUMBER}${TAG}
LOG_GROUP=${LOG_GROUP//[-.]/}
LOG_STREAM=pgfm${USER}ls${TAG}
LOG_STREAM=${LOG_STREAM//[-.]/}

TOPIC="$LOG_GROUP.$LOG_STREAM"

log "Creating $TOPIC topic"
set +e
playground topic delete --topic $TOPIC
sleep 3
playground topic create --topic $TOPIC
set -e

# cleanup
set +e
aws logs delete-log-group --log-group-name $LOG_GROUP
set -e

log "Create a log group in AWS CloudWatch Logs."
aws logs create-log-group --log-group-name $LOG_GROUP

log "Create a log stream in AWS CloudWatch Logs."
aws logs create-log-stream --log-group-name $LOG_GROUP --log-stream $LOG_STREAM

connector_name="CloudWatchLogsSource_$USER"
set +e
playground connector delete --connector $connector_name > /dev/null 2>&1
set -e


function cleanup_cloud_resources {
    set +e
    log "Do you want to delete the log group $LOG_GROUP (connector will be deleted first)?"
    check_if_continue
    playground connector delete --connector $connector_name

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

log "Creating AWS CloudWatch Logs Source connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "connector.class": "CloudWatchLogsSource",
    "name": "$connector_name",
    "kafka.auth.mode": "KAFKA_API_KEY",
    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "output.data.format": "AVRO",
    "aws.cloudwatch.logs.url": "https://logs.$AWS_REGION.amazonaws.com",
    "aws.cloudwatch.log.group": "$LOG_GROUP",
    "aws.cloudwatch.log.streams": "$LOG_STREAM",
    "tasks.max" : "1"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

log "Verify we have received the data in $TOPIC topic"
playground topic consume --topic $TOPIC --min-expected-messages 10 --timeout 60

log "Do you want to delete the fully managed connector $connector_name ?"
check_if_continue

playground connector delete --connector $connector_name