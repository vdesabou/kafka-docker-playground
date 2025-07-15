#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.3.99"; then
    logwarn "Tiered Storage is available since CP 5.4 only"
    exit 111
fi

if [ ! -f $HOME/.aws/credentials ] && ( [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] )
then
     logerror "❌ either the file $HOME/.aws/credentials is not present or environment variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set!"
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
            logerror "❌ either the file $HOME/.aws/config is not present or environment variables AWS_REGION is not set!"
            exit 1
        fi
    fi
fi

export AWS_REGION=$(aws configure get region | tr '\r' '\n')

AWS_BUCKET_TIERED_STORAGE=pg-bucket-${USER}
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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Create topic TieredStorage"
docker exec broker kafka-topics --bootstrap-server 127.0.0.1:9092 --create --topic TieredStorage --partitions 6 --replication-factor 1 --config confluent.tier.enable=true --config confluent.tier.local.hotset.ms=60000 --config retention.ms=86400000

log "Sending messages to topic TieredStorage"
playground topic produce -t TieredStorage --nb-messages 200000 << 'EOF'
This is my message %g
EOF

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