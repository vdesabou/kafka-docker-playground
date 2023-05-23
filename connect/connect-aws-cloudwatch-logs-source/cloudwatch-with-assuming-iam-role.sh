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

LOG_GROUP=my-log-group$TAG
LOG_GROUP=${LOG_GROUP//[-.]/}
LOG_STREAM=my-log-stream$TAG
LOG_STREAM=${LOG_STREAM//[-.]/}

# cleanup
set +e
aws logs delete-log-group --log-group-name $LOG_GROUP
set -e

log "Create a log group in AWS CloudWatch Logs."
aws logs create-log-group --log-group-name $LOG_GROUP

log "Create a log stream in AWS CloudWatch Logs."
aws logs create-log-stream --log-group-name $LOG_GROUP --log-stream $LOG_STREAM

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
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.aws.cloudwatch.AwsCloudWatchSourceConnector",
               "tasks.max": "1",
               "aws.cloudwatch.logs.url": "'"$CLOUDWATCH_LOGS_URL"'",
               "aws.cloudwatch.log.group": "'"$LOG_GROUP"'",
               "aws.cloudwatch.log.streams": "'"$LOG_STREAM"'",
               "confluent.license": "",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/aws-cloudwatch-logs-source/config | jq .

sleep 5

log "Verify we have received the data in $LOG_GROUP.$LOG_STREAM topic"
playground topic consume --topic $LOG_GROUP.$LOG_STREAM --min-expected-messages 11
