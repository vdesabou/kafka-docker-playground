#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f confluentinc-kafka-connect-s3-10.5.13.zip ]
then
    log "Downloading confluentinc-kafka-connect-s3-10.5.13.zip from confluent hub"
    wget -q https://d2p6pa21dvn84.cloudfront.net/api/plugins/confluentinc/kafka-connect-s3/versions/10.5.13/confluentinc-kafka-connect-s3-10.5.13.zip
fi

plugin_name="pg_${USER}_s3_sink_10_5_13"

set +e
for row in $(confluent connect custom-plugin list --output json | jq -r '.[] | @base64'); do
    _jq() {
    echo ${row} | base64 -d | jq -r ${1}
    }
    
    id=$(echo $(_jq '.id'))
    name=$(echo $(_jq '.name'))

    if [[ "$name" = "$plugin_name" ]]
    then
        log "deleting plugin $id ($name)"
        confluent connect custom-plugin delete $id --force
    fi
done
set -e

log "Uploading custom plugin $plugin_name"
confluent connect custom-plugin create $plugin_name --plugin-file confluentinc-kafka-connect-s3-10.5.13.zip --connector-class io.confluent.connect.s3.S3SinkConnector --connector-type SINK --sensitive-properties "aws.secret.access.key"
ret=$?

function cleanup_resources {
    log "Do you want to delete the custom plugin $plugin_name ($plugin_id) and custom connector $connector_name ?"
    check_if_continue

    playground connector delete --connector $connector_name
    confluent connect custom-plugin delete $plugin_id --force
}
trap cleanup_resources EXIT

set -e
if [ $ret -eq 0 ]
then
    found=0
    set +e
    for row in $(confluent connect custom-plugin list --output json | jq -r '.[] | @base64'); do
        _jq() {
        echo ${row} | base64 -d | jq -r ${1}
        }
        
        id=$(echo $(_jq '.id'))
        name=$(echo $(_jq '.name'))

        if [[ "$name" = "$plugin_name" ]]
        then
            plugin_id="$id"
            log "custom plugin $plugin_name ($plugin_id) was successfully uploaded!"
            found=1
            break
        fi
    done
else
    logerror "❌ command failed with error code $ret!"
    exit 1
fi
set -e
if [ $found -eq 0 ]
then
     logerror "❌ plugin could not be uploaded !"
     exit 1
fi

handle_aws_credentials

bootstrap_ccloud_environment



AWS_BUCKET_NAME=pg-bucket-${USER}
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

log "Creating s3_topic topic in Confluent Cloud (auto.create.topics.enable=false)"
set +e
playground topic create --topic s3_topic
set -e

log "Sending messages to topic s3_topic"
playground topic produce -t s3_topic --nb-messages 9 --forced-value '{"f1":"value%g"}' << 'EOF'
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

playground topic produce -t s3_topic --nb-messages 9 << 'EOF'
this is bad record
EOF

connector_name="S3_SINK_CUSTOM_$USER"
set +e
log "Deleting confluent cloud custom connector $connector_name, it might fail..."
playground connector delete --connector $connector_name
set -e

log "Creating confluent cloud custom connector"
playground connector create-or-update --connector $connector_name << EOF
{
    "confluent.connector.type": "CUSTOM",
    "confluent.custom.plugin.id": "$plugin_id",
    "confluent.custom.connection.endpoints": "s3.$AWS_REGION.amazonaws.com:443:TCP",

    "kafka.api.key": "$CLOUD_KEY",
    "kafka.api.secret": "$CLOUD_SECRET",
    "name": "$connector_name",
    "tasks.max": "1",
    "topics": "s3_topic",
    "s3.region": "$AWS_REGION",
    "s3.bucket.name": "$AWS_BUCKET_NAME",
    "topics.dir": "$TAG",
    "s3.part.size": "52428801",
    "flush.size": "3",
    "aws.access.key.id" : "$AWS_ACCESS_KEY_ID",
    "aws.secret.access.key": "$AWS_SECRET_ACCESS_KEY",
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "schema.compatibility": "NONE",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",

    "confluent.custom.schema.registry.auto": "true",
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",

    "errors.tolerance": "all",
    "errors.deadletterqueue.topic.name": "dlq",
    "errors.deadletterqueue.topic.replication.factor": "3",
    "errors.deadletterqueue.context.headers.enable": "true",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true"
}
EOF
wait_for_ccloud_connector_up $connector_name 180

sleep 10

# log "Listing objects of in S3"
# aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp --only-show-errors s3://$AWS_BUCKET_NAME/$TAG/s3_topic/partition=0/s3_topic+0+0000000000.avro s3_topic+0+0000000000.avro

playground tools read-avro-file --file $PWD/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro