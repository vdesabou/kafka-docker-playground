#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh


tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
trap 'rm -rf $tmp_dir' EXIT
export TMP_CREDENTIALS_FILE="$tmp_dir/credentials"

if [ ! -z $AWS_ACCESS_KEY_ID ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ] && [ ! -z "$AWS_SESSION_TOKEN" ]
then
    log "💭 Using environment variables AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN"
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN

cat << EOF > $TMP_CREDENTIALS_FILE
[default]
aws_access_key_id=$AWS_ACCESS_KEY_ID
aws_secret_access_key=$AWS_SECRET_ACCESS_KEY
aws_session_token=$AWS_SESSION_TOKEN
EOF
elif grep -q "aws_session_token" $HOME/.aws/credentials
then
    head -4 $HOME/.aws/credentials > $TMP_CREDENTIALS_FILE

    set +e
    grep -q default $TMP_CREDENTIALS_FILE
    if [ $? != 0 ]
    then
        logerror "$HOME/.aws/credentials does not have expected format, the 4 first lines must be:"
        echo "[default]"
        echo "aws_access_key_id=<AWS_ACCESS_KEY_ID>"
        echo "aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>"
        echo "aws_session_token=<AWS_SESSION_TOKEN>"
        exit 1
    fi
    grep -q aws_session_token $TMP_CREDENTIALS_FILE
    if [ $? != 0 ]
    then
        logerror "$HOME/.aws/credentials does not have expected format, the 4 first lines must be:"
        echo "[default]"
        echo "aws_access_key_id=<AWS_ACCESS_KEY_ID>"
        echo "aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>"
        echo "aws_session_token=<AWS_SESSION_TOKEN>"
        exit 1
    fi
    set +e
fi

log "✨ Using credentials file $TMP_CREDENTIALS_FILE"

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

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.with-short-lived-creds.yml"

AWS_BUCKET_NAME=pg-bucket-${USER}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}


log "Create bucket <$AWS_BUCKET_NAME>, if required"
set +e
if [ "$AWS_REGION" == "us-east-1" ]
then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
set -e
log "Empty bucket <$AWS_BUCKET_NAME/$TAG>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME/$TAG --recursive --region $AWS_REGION
set -e

log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
playground connector create-or-update --connector s3-sink  << EOF
{
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "tasks.max": "1",
    "topics": "s3_topic",
    "s3.region": "$AWS_REGION",
    "s3.bucket.name": "$AWS_BUCKET_NAME",
    "topics.dir": "$TAG",
    "s3.part.size": "52428801",
    "flush.size": "3",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
    "schema.compatibility": "NONE"
}
EOF

log "Sending messages to topic s3_topic"
playground topic produce -t s3_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
{
  "type": "record",
  "name": "myrecord",
  "fields": [
    {
      "name": "f1",
      "type": "string"
    }
  ]
}
EOF

sleep 10

# log "Listing objects of in S3"
# aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp --only-show-errors s3://$AWS_BUCKET_NAME/$TAG/s3_topic/partition=0/s3_topic+0+0000000000.avro s3_topic+0+0000000000.avro

docker run --rm -v ${DIR}:/tmp vdesabou/avro-tools tojson /tmp/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro