#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $CONNECTOR_TAG "1.9.9"; then
    # skipped
    logwarn "WARN: skipped as it requires connector version 2.0.0"
    exit 111
fi

if ! version_gt $TAG_BASE "5.9.99" && version_gt $CONNECTOR_TAG "1.9.9"
then
    logwarn "WARN: connector version >= 2.0.0 do not support CP versions < 6.0.0"
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

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.generalized.yml"

AWS_BUCKET_NAME=pg-bucket-${USER}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}



log "Empty bucket <$AWS_BUCKET_NAME/$TAG>, if required"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME/$TAG --recursive --region $AWS_REGION
set -e


log "Copy generalized.quickstart.json to bucket $AWS_BUCKET_NAME/quickstart"
aws s3 cp generalized.quickstart.json s3://$AWS_BUCKET_NAME/quickstart/generalized.quickstart.json

log "Creating Generalized S3 Source connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "aws.access.key.id" : "'"$AWS_ACCESS_KEY_ID"'",
               "aws.secret.access.key": "'"$AWS_SECRET_ACCESS_KEY"'",
               "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
               "value.converter": "org.apache.kafka.connect.json.JsonConverter",
               "value.converter.schemas.enable": "false",
               "confluent.license": "",
               "mode": "GENERIC",
               "topics.dir": "quickstart",
               "topic.regex.list": "quick-start-topic:.*",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "errors.tolerance": "all",
               "errors.log.enable": "true",
               "errors.log.include.messages": "true"
          }' \
     http://localhost:8083/connectors/s3-source-generalized/config | jq .


log "Verifying topic quick-start-topic"
timeout 60 docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic quick-start-topic --from-beginning --max-messages 9
