#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "WARN: Tiered Storage is available since CP 5.4 only"
    exit 111
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
export AWS_REGION=$(aws configure get region | tr '\r' '\n')

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
     logerror "AWS_REGION is not set. Check your $HOME/.aws/config file"
     exit 1
fi

AWS_BUCKET_TIERED_STORAGE=aws-playground-tiered-storage$TAG
AWS_BUCKET_TIERED_STORAGE=${AWS_BUCKET_TIERED_STORAGE//[-.]/}
export AWS_BUCKET_TIERED_STORAGE

log "Create bucket $AWS_BUCKET_TIERED_STORAGE in S3"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_TIERED_STORAGE --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket $AWS_BUCKET_TIERED_STORAGE, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_TIERED_STORAGE --recursive --region $AWS_REGION
set -e

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Create topic TieredStorage"
docker exec broker kafka-topics --bootstrap-server 127.0.0.1:9092 --create --topic TieredStorage --partitions 6 --replication-factor 1 --config confluent.tier.enable=true --config confluent.tier.local.hotset.ms=60000 --config retention.ms=86400000

log "Sending messages to topic TieredStorage"
seq -f "This is a message %g" 200000 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic TieredStorage

sleep 10

log "Check for uploaded log segments"
docker container logs broker | grep "Uploaded"

log "Listing objects of bucket $AWS_BUCKET_TIERED_STORAGE in S3"
aws s3api list-objects --bucket $AWS_BUCKET_TIERED_STORAGE

log "Sleep 6 minutes (confluent.tier.local.hotset.ms=60000)"
sleep 360

log "Check for deleted log segments"
docker container logs broker | grep "Deleted log"

log "Empty bucket $AWS_BUCKET_TIERED_STORAGE in S3"
aws s3 rm s3://$AWS_BUCKET_TIERED_STORAGE --recursive
log "Delete bucket $AWS_BUCKET_TIERED_STORAGE in S3"
aws s3api delete-bucket --bucket $AWS_BUCKET_TIERED_STORAGE