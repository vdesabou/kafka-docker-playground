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
            export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $HOME/.aws/credentials| awk -F'=' '{print $2;}' )
            export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $HOME/.aws/credentials| awk -F'=' '{print $2;}' ) 
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

if [ -f /tmp/delta_configs/env.delta ]
then
     source /tmp/delta_configs/env.delta
else
     logerror "ERROR: /tmp/delta_configs/env.delta has not been generated"
     exit 1
fi


LOG_GROUP=my-log-group$TAG
LOG_GROUP=${LOG_GROUP//[-.]/}
LOG_STREAM=my-log-stream$TAG
LOG_STREAM=${LOG_STREAM//[-.]/}

TOPIC="$LOG_GROUP.$LOG_STREAM"

log "Creating $TOPIC topic"
set +e
delete_topic $TOPIC
sleep 3
create_topic $TOPIC
set -e

# cleanup
set +e
aws logs delete-log-group --log-group $LOG_GROUP
set -e

log "Create a log group in AWS CloudWatch Logs."
aws logs create-log-group --log-group $LOG_GROUP

log "Create a log stream in AWS CloudWatch Logs."
aws logs create-log-stream --log-group $LOG_GROUP --log-stream $LOG_STREAM

log "Insert Records into your log stream."
# If this is the first time inserting logs into a new log stream, then no sequence token is needed.
# However, after the first put, there will be a sequence token returned that will be needed as a parameter in the next put.
aws logs put-log-events --log-group $LOG_GROUP --log-stream $LOG_STREAM --log-events timestamp=`date +%s000`,message="This is a log #0"

log "Injecting more messages"
for i in $(seq 1 10)
do
     token=$(aws logs describe-log-streams --log-group $LOG_GROUP | jq -r .logStreams[0].uploadSequenceToken)
     aws logs put-log-events --log-group $LOG_GROUP --log-stream $LOG_STREAM --log-events timestamp=`date +%s000`,message="This is a log #${i}" --sequence-token ${token}
done

cat << EOF > connector.json
{
    "connector.class": "CloudWatchLogsSource",
    "name": "CloudWatchLogsSource",
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

log "Connector configuration is:"
cat connector.json

set +e
log "Deleting fully managed connector, it might fail..."
delete_ccloud_connector connector.json
set -e

log "Creating fully managed connector"
create_ccloud_connector connector.json
wait_for_ccloud_connector_up connector.json 300

log "Verify we have received the data in $TOPIC topic"
timeout 60 docker run --rm -e BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVERS" -e SASL_JAAS_CONFIG="$SASL_JAAS_CONFIG" -e SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" -e SCHEMA_REGISTRY_URL="$SCHEMA_REGISTRY_URL" ${CP_CONNECT_IMAGE}:${CONNECT_TAG} kafka-avro-console-consumer --topic $TOPIC --bootstrap-server $BOOTSTRAP_SERVERS --consumer-property ssl.endpoint.identification.algorithm=https --consumer-property sasl.mechanism=PLAIN --consumer-property security.protocol=SASL_SSL --consumer-property sasl.jaas.config="$SASL_JAAS_CONFIG" --property basic.auth.credentials.source=USER_INFO --property schema.registry.basic.auth.user.info="$SCHEMA_REGISTRY_BASIC_AUTH_USER_INFO" --property schema.registry.url=$SCHEMA_REGISTRY_URL --from-beginning --property print.key=true  --property key.deserializer=org.apache.kafka.common.serialization.StringDeserializer --max-messages 10 --property print.key=true

# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092839000} "This is a log #0"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092841000} "This is a log #1"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092844000} "This is a log #2"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092846000} "This is a log #3"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092848000} "This is a log #4"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092851000} "This is a log #5"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092853000} "This is a log #6"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092856000} "This is a log #7"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092858000} "This is a log #8"
# Struct{logGroupName=myloggroup731,logStreamName=mylogstream731,timestamp=1675092861000} "This is a log #9"
