#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
BUCKET_NAME=${1:-kafka-docker-playground} 

${DIR}/../reset-cluster.sh

echo "Creating S3 Sink connector with bucket name <$BUCKET_NAME>"
docker-compose exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "s3-sink",
               "config": {
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
          }}' \
     http://localhost:8083/connectors | jq .


echo "Sending messages to topic s3_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic s3_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'

sleep 10

echo "Listing objects of in S3"
aws s3api list-objects --bucket "$BUCKET_NAME"

echo "Getting one of the avro files locally and displaying content with avro-tools"
aws s3 cp s3://$BUCKET_NAME/topics/s3_topic/partition=0/s3_topic+0+0000000000.avro /tmp/

# brew install avro-tools
avro-tools tojson /tmp/s3_topic+0+0000000000.avro

echo "Creating S3 Source connector with bucket name <$BUCKET_NAME>"
docker-compose exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "s3-source3",
               "config": {
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
          }}' \
     http://localhost:8083/connectors | jq .
