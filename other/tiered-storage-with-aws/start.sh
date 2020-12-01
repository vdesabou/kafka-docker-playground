#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.2"; then
    logwarn "WARN: Tiered storage is only available from Confluent Platform 5.4.0"
    exit 0
fi

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
AWS_CREDENTIAL_FILE=$HOME/.aws/credentials
if [ ! -f $AWS_CREDENTIAL_FILE ]
then
     logerror "ERROR: $AWS_CREDENTIAL_FILE is not set"
     exit 1
fi

export AWS_ACCESS_KEY_ID=$( grep "^aws_access_key_id" $AWS_CREDENTIAL_FILE | awk -F'=' '{print $2;}' )
export AWS_SECRET_ACCESS_KEY=$( grep "^aws_secret_access_key" $AWS_CREDENTIAL_FILE | awk -F'=' '{print $2;}' )
export AWS_REGION=$( grep "^region" $AWS_CREDENTIAL_FILE | awk -F'=' '{print $2;}' )

if [ -z "$AWS_ACCESS_KEY_ID" ]
then
     logerror "AWS_ACCESS_KEY_ID is not set. Check your $AWS_CREDENTIAL_FILE file"
     exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]
then
     logerror "AWS_SECRET_ACCESS_KEY is not set. Check your $AWS_CREDENTIAL_FILE file"
     exit 1
fi

if [ -z "$AWS_REGION" ]
then
     logerror "AWS_REGION is not set. Check your $AWS_CREDENTIAL_FILE file"
     exit 1
fi

log "Create bucket aws-playground-tiered-storage in S3"
set +e
aws s3api create-bucket --bucket aws-playground-tiered-storage --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.yml" -a -b

log "Create topic TieredStorage"
docker exec broker kafka-topics --bootstrap-server 127.0.0.1:9092 --create --topic TieredStorage --partitions 6 --replication-factor 1 --config confluent.tier.enable=true --config confluent.tier.local.hotset.ms=60000 --config retention.ms=86400000

log "Sending messages to topic TieredStorage"
seq -f "This is a message %g" 200000 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic TieredStorage

sleep 10

log "Check for uploaded log segments"
docker container logs broker | grep "Uploaded"

log "Listing objects of bucket aws-playground-tiered-storage in S3"
aws s3api list-objects --bucket aws-playground-tiered-storage

log "Sleep 5 minutes (confluent.tier.local.hotset.ms=60000)"
sleep 300

log "Check for deleted log segments"
docker container logs broker | grep "Deleted log"

log "Empty bucket aws-playground-tiered-storage in S3"
aws s3 rm s3://aws-playground-tiered-storage --recursive
log "Delete bucket aws-playground-tiered-storage in S3"
aws s3api delete-bucket --bucket aws-playground-tiered-storage