#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
BUCKET_NAME=${1:-test-gcs-playground} 

KEYFILE="${DIR}/../keyfiles/keyfile_gcs.json"
if [ ! -f ${KEYFILE} ]
then
     echo "ERROR: the file ${KEYFILE} file is not present!"
     exit 1
fi

${DIR}/../scripts/reset-cluster.sh

echo "Removing existing objects in GCS, if applicable"
gsutil rm -r gs://$BUCKET_NAME/topics/gcs_topic

echo "Sending messages to topic gcs_topic"
seq -f "{\"f1\": \"value%g\"}" 10 | docker container exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic gcs_topic --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"f1","type":"string"}]}'


echo "Creating GCS Sink connector"
docker-compose exec -e BUCKET_NAME="$BUCKET_NAME" connect \
     curl -X POST \
     -H "Content-Type: application/json" \
     --data '{
               "name": "gcs",
               "config": {
                    "connector.class": "io.confluent.connect.gcs.GcsSinkConnector",
                    "tasks.max" : "1",
                    "topics" : "gcs_topic",
                    "gcs.bucket.name" : "'"$BUCKET_NAME"'",
                    "gcs.part.size": "5242880",
                    "flush.size": "3",
                    "gcs.credentials.path": "/root/keyfiles/keyfile_gcs.json",
                    "storage.class": "io.confluent.connect.gcs.storage.GcsStorage",
                    "format.class": "io.confluent.connect.gcs.format.avro.AvroFormat",
                    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
                    "schema.compatibility": "NONE",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }}' \
     http://localhost:8083/connectors | jq .

echo "Listing objects of in GCS"
gsutil ls gs://$BUCKET_NAME/topics/gcs_topic/partition=0/

echo "Doing gsutil authentication"
gcloud auth activate-service-account --key-file ${KEYFILE}

echo "Getting one of the avro files locally and displaying content with avro-tools"
gsutil cp gs://$BUCKET_NAME/topics/gcs_topic/partition=0/gcs_topic+0+0000000000.avro /tmp/

# brew install avro-tools
avro-tools tojson /tmp/gcs_topic+0+0000000000.avro
