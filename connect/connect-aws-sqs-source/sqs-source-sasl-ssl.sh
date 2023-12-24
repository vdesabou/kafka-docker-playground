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

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

playground start-environment --environment sasl-ssl --docker-compose-override-file "${PWD}/docker-compose.sasl-ssl.yml"

QUEUE_NAME=pg${USER}sqs${TAG}
QUEUE_NAME=${QUEUE_NAME//[-._]/}

QUEUE_URL_RAW=$(aws sqs create-queue --queue-name $QUEUE_NAME | jq .QueueUrl)
AWS_ACCOUNT_NUMBER=$(echo "$QUEUE_URL_RAW" | cut -d "/" -f 4)
# https://docs.amazonaws.cn/sdk-for-net/v3/developer-guide/how-to/sqs/QueueURL.html
# https://{REGION_ENDPOINT}/queue.|api-domain|/{YOUR_ACCOUNT_NUMBER}/{YOUR_QUEUE_NAME}
QUEUE_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_NUMBER/$QUEUE_NAME"

set +e
log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
if [ $? -eq 0 ]
then
     # You must wait 60 seconds after deleting a queue before you can create another with the same name
     log "Sleeping 60 seconds"
     sleep 60
fi
set -e

log "########"
log "##  SASL_SSL authentication"
log "########"

log "Create a FIFO queue $QUEUE_NAME"
aws sqs create-queue --queue-name $QUEUE_NAME

log "Sending messages to $QUEUE_URL"
cd ../../connect/connect-aws-sqs-source
aws sqs send-message-batch --queue-url $QUEUE_URL --entries file://send-message-batch.json
cd -


log "Creating SQS Source connector with SASL_SSL authentication"
playground connector create-or-update --connector sqs-source-sasl-ssl  << EOF
{
    "connector.class": "io.confluent.connect.sqs.source.SqsSourceConnector",
    "tasks.max": "1",
    "kafka.topic": "test-sqs-source-sasl-ssl",
    "sqs.url": "$QUEUE_URL",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.key.id": "$AWS_SECRET_ACCESS_KEY",
    "confluent.license": "",
    "confluent.topic.bootstrap.servers": "broker:9092",
    "confluent.topic.replication.factor": "1",
    "confluent.topic.ssl.keystore.location" : "/etc/kafka/secrets/kafka.connect.keystore.jks",
    "confluent.topic.ssl.keystore.password" : "confluent",
    "confluent.topic.ssl.key.password" : "confluent",
    "confluent.topic.ssl.truststore.location" : "/etc/kafka/secrets/kafka.connect.truststore.jks",
    "confluent.topic.ssl.truststore.password" : "confluent",
    "confluent.topic.security.protocol" : "SASL_SSL",
    "confluent.topic.sasl.mechanism": "PLAIN",
    "confluent.topic.sasl.jaas.config": "org.apache.kafka.common.security.plain.PlainLoginModule required  username=\"client\" password=\"client-secret\";",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF

sleep 10

log "Verify we have received the data in test-sqs-source-sasl-ssl topic"
playground topic consume --topic test-sqs-source-sasl-ssl --min-expected-messages 2 --timeout 60

log "Delete queue ${QUEUE_URL}"
aws sqs delete-queue --queue-url ${QUEUE_URL}
