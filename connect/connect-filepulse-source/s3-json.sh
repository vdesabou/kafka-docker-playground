#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if ! version_gt $TAG_BASE "5.9.0"
then
    if version_gt $CONNECTOR_TAG "1.9.9"
    then
        log "This connector does not support JDK 8 starting from version 2.0"
        exit 111
    fi
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

if ! version_gt $CONNECTOR_TAG "1.9.9"
then
     logerror "This is only available with connector version starting from 2.0"
     exit 1
fi

AWS_BUCKET_NAME=kafka-docker-playground-filepulse-bucket-${USER}${TAG}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}


log "Empty bucket <$AWS_BUCKET_NAME/$TAG>, if required"
set +e
if [ "$AWS_REGION" == "us-east-1" ]
then
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION
else
    aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME/$TAG --recursive --region $AWS_REGION
set -e

# generate data file for externalizing secrets
sed -e "s|:AWS_ACCESS_KEY_ID:|$AWS_ACCESS_KEY_ID|g" \
    -e "s|:AWS_SECRET_ACCESS_KEY:|$AWS_SECRET_ACCESS_KEY|g" \
    ../../connect/connect-filepulse-source/data.template > ../../connect/connect-filepulse-source/data

log "Generating data"
cat <<EOF > /tmp/track.json
{
  "track": {
     "title":"Star Wars (Main Theme)",
     "artist":"John Williams, London Symphony Orchestra",
     "album":"Star Wars",
     "duration":"10:52"
  }
}
EOF
log "Upload JSON file to AWS S3 bucket $AWS_BUCKET_NAME"
aws s3 cp /tmp/track.json s3://$AWS_BUCKET_NAME/

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.s3.yml"

log "Creating S3 JSON FilePulse Source connector"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "connector.class":"io.streamthoughts.kafka.connect.filepulse.source.FilePulseSourceConnector",
          "aws.access.key.id": "${file:/data:aws.access.key.id}",
          "aws.secret.access.key": "${file:/data:aws.secret.access.key}",
          "aws.s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
          "aws.s3.region": "'"$AWS_REGION"'",
          "fs.listing.class": "io.streamthoughts.kafka.connect.filepulse.fs.AmazonS3FileSystemListing",
          "fs.listing.filters":"io.streamthoughts.kafka.connect.filepulse.fs.filter.RegexFileListFilter",
          "fs.listing.interval.ms": "10000",
          "file.filter.regex.pattern":".*\\.json$",
          "offset.attributes.string": "uri",
          "tasks.reader.class": "io.streamthoughts.kafka.connect.filepulse.fs.reader.AmazonS3BytesArrayInputReader",
          "offset.strategy":"name",
          "topic":"tracks-filepulse-json-00",
          "internal.kafka.reporter.bootstrap.servers": "broker:9092",
          "internal.kafka.reporter.topic":"connect-file-pulse-status",
          "fs.cleanup.policy.class": "io.streamthoughts.kafka.connect.filepulse.fs.clean.LogCleanupPolicy",
          "filters": "ParseJSON",
          "filters.ParseJSON.type":"io.streamthoughts.kafka.connect.filepulse.filter.JSONFilter",
          "filters.ParseJSON.source":"message",
          "filters.ParseJSON.merge":"true",
          "tasks.file.status.storage.class": "io.streamthoughts.kafka.connect.filepulse.state.KafkaFileObjectStateBackingStore",
          "tasks.file.status.storage.bootstrap.servers": "broker:9092",
          "tasks.file.status.storage.topic": "connect-file-pulse-status",
          "tasks.file.status.storage.topic.partitions": 10,
          "tasks.file.status.storage.topic.replication.factor": 1,
          "tasks.max": 1
          }' \
     http://localhost:8083/connectors/filepulse-source-s3-json/config | jq .


sleep 5

log "Verify we have received the data in tracks-filepulse-json-00 topic"
timeout 60 docker exec connect kafka-avro-console-consumer -bootstrap-server broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic tracks-filepulse-json-00 --from-beginning --max-messages 1