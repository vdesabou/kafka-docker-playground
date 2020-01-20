#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
BUCKET_NAME=${1:-kafka-docker-playground}

if [ ! -f $HOME/.aws/config ]
then
     logerror "ERROR: $HOME/.aws/config is not set"
     exit 1
fi
if [ ! -f $HOME/.aws/credentials ]
then
     logerror "ERROR: $HOME/.aws/credentials is not set"
     exit 1
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


log "Creating S3 Sink connector with bucket name <$BUCKET_NAME>"
docker exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.s3.S3SinkConnector",
                    "tasks.max": "1",
                    "topics": "s3_topic",
                    "s3.region": "us-east-1",
                    "s3.bucket.name": "'"$BUCKET_NAME"'",
                    "s3.part.size": 5242880,
                    "flush.size": "3",
                    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
                    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE"
          }' \
     http://localhost:8083/connectors/s3-sink/config | jq_docker_cli .


log "Sending messages to topic s3_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker exec -i connect kafka-avro-console-producer --broker-list broker:9092 --property schema.registry.url=http://schema-registry:8081 --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

log "Listing objects of in S3"
aws_docker_cli s3api list-objects --bucket "$BUCKET_NAME"

log "Getting one of the avro files locally and displaying content with avro-tools"
aws_docker_cli s3 cp s3://$BUCKET_NAME/topics/s3_topic/partition=0/s3_topic+0+0000000000.avro s3_topic+0+0000000000.avro

docker run -v ${DIR}:/tmp actions/avro-tools tojson /tmp/s3_topic+0+0000000000.avro
rm -f s3_topic+0+0000000000.avro

log "Creating S3 Source connector with bucket name <$BUCKET_NAME>"
docker exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "tasks.max": "1",
                    "connector.class": "io.confluent.connect.s3.source.S3SourceConnector",
                    "s3.region": "us-east-1",
                    "s3.bucket.name": "'"$BUCKET_NAME"'",
                    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
                    "confluent.license": "",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1",
                    "transforms": "AddPrefix",
                    "transforms.AddPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
                    "transforms.AddPrefix.regex": ".*",
                    "transforms.AddPrefix.replacement": "copy_of_$0"
          }' \
     http://localhost:8083/connectors/s3-source/config | jq_docker_cli .


log "Verifying topic copy_of_s3_topic"
docker exec broker kafka-console-consumer -bootstrap-server broker:9092 --topic copy_of_s3_topic --from-beginning --max-messages 9
