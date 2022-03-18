#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ -z "$AWS_CREDENTIALS_FILE_NAME" ]
then
    export AWS_CREDENTIALS_FILE_NAME="credentials"
fi
if [ ! -f $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME ]
then
     logerror "ERROR: $HOME/.aws/$AWS_CREDENTIALS_FILE_NAME is not set"
     exit 1
fi

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.repro-97575-inconsistentgroupprotocolexception.yml"

AWS_BUCKET_NAME=kafka-docker-playground-bucket-${USER}${TAG}
AWS_BUCKET_NAME=${AWS_BUCKET_NAME//[-.]/}

AWS_REGION=$(aws configure get region | tr '\r' '\n')
log "Creating bucket name <$AWS_BUCKET_NAME>, if required"
set +e
aws s3api create-bucket --bucket $AWS_BUCKET_NAME --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
set -e
log "Empty bucket <$AWS_BUCKET_NAME>, if required"
set +e
aws s3 rm s3://$AWS_BUCKET_NAME --recursive --region $AWS_REGION
set -e

log "Creating S3 Sink connector with bucket name <$AWS_BUCKET_NAME>"
curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
               "tasks.max": "1",
               "topics": "s3_topic",
               "s3.region": "'"$AWS_REGION"'",
               "s3.bucket.name": "'"$AWS_BUCKET_NAME"'",
               "s3.part.size": 52428801,
               "flush.size": "3",
               "storage.class": "io.confluent.connect.s3.storage.S3Storage",
               "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
               "schema.compatibility": "NONE"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq .


# [2022-03-18 09:36:56,787] WARN [s3-sink|task-0] [Consumer clientId=connect-topic-backup, groupId=connect-topic-backup] Error while fetching metadata with correlation id 2 : {s3_topic=LEADER_NOT_AVAILABLE} (org.apache.kafka.clients.NetworkClient:1213)
# [2022-03-18 09:36:56,787] INFO [s3-sink|task-0] [Consumer clientId=connect-topic-backup, groupId=connect-topic-backup] Cluster ID: PFO-nLmcSLilpJtISG15lw (org.apache.kafka.clients.Metadata:287)
# [2022-03-18 09:36:56,789] INFO [s3-sink|task-0] [Consumer clientId=connect-topic-backup, groupId=connect-topic-backup] Discovered group coordinator broker:9092 (id: 2147483646 rack: null) (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:849)
# [2022-03-18 09:36:56,791] INFO [s3-sink|task-0] [Consumer clientId=connect-topic-backup, groupId=connect-topic-backup] (Re-)joining group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:535)
# [2022-03-18 09:36:56,825] ERROR [s3-sink|task-0] [Consumer clientId=connect-topic-backup, groupId=connect-topic-backup] JoinGroup failed due to fatal error: The group member's supported protocols are incompatible with those of existing members or first group member tried to join with empty protocol type or empty protocol list. (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:633)
# [2022-03-18 09:36:56,831] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:206)
# org.apache.kafka.common.errors.InconsistentGroupProtocolException: The group member's supported protocols are incompatible with those of existing members or first group member tried to join with empty protocol type or empty protocol list.
# [2022-03-18 09:36:56,833] INFO [s3-sink|task-0] [Consumer clientId=connect-topic-backup, groupId=connect-topic-backup] Resetting generation due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:966)
# [2022-03-18 09:36:56,840] INFO [s3-sink|task-0] [Consumer clientId=connect-topic-backup, groupId=connect-topic-backup] Request joining group due to: consumer pro-actively leaving the group (org.apache.kafka.clients.consumer.internals.ConsumerCoordinator:988)
# [2022-03-18 09:36:56,841] INFO [s3-sink|task-0] Metrics scheduler closed (org.apache.kafka.common.metrics.Metrics:676)
# [2022-03-18 09:36:56,841] INFO [s3-sink|task-0] Closing reporter org.apache.kafka.common.metrics.JmxReporter (org.apache.kafka.common.metrics.Metrics:680)
# [2022-03-18 09:36:56,842] INFO [s3-sink|task-0] Metrics reporters closed (org.apache.kafka.common.metrics.Metrics:686)
# [2022-03-18 09:36:56,847] INFO [s3-sink|task-0] App info kafka.consumer for connect-topic-backup unregistered (org.apache.kafka.common.utils.AppInfoParser:83)

log "Sending messages to topic s3_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing objects of in S3"
aws s3api list-objects --bucket "$AWS_BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp --only-show-errors s3://$AWS_BUCKET_NAME/topics/s3_topic/partition=0/s3_topic+0+0000000000.avro s3_topic+0+0000000000.avro

docker run --rm -v ${DIR}:/tmp actions/avro-tools tojson /tmp/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro