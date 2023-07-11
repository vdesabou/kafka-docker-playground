#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if [[ "$TAG" == *ubi8 ]] || version_gt $TAG_BASE "5.9.0"
then
     export CONNECT_CONTAINER_HOME_DIR="/home/appuser"
else
     export CONNECT_CONTAINER_HOME_DIR="/root"
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"

log "Minio UI is accessible at http://127.0.0.1:9000 (AKIAIOSFODNN7EXAMPLE/wJalrXUtnFEMI7K7MDENG8bPxRfiCYEXAMPLEKEY)"

log "Creating bucket in Minio"
docker container restart create-buckets

log "Creating S3 Sink connector with Minio"
playground connector create-or-update --connector minio-sink << EOF
{
     "connector.class": "io.confluent.connect.s3.S3SinkConnector",
     "tasks.max": "1",
     "topics": "minio_topic",
     "s3.bucket.name": "mybucket",
     "s3.part.size": 5242880,
     "store.url": "http://minio:9000",
     "flush.size": "3",
     "storage.class": "io.confluent.connect.s3.storage.S3Storage",
     "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
     "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
     "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
     "schema.compatibility": "NONE"
}
EOF


log "Sending messages to topic minio_topic"
playground topic produce -t minio_topic --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
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

log "Listing objects of bucket mybucket in Minio"
docker container restart list-buckets
sleep 3
docker container logs --tail=4 list-buckets

log "Getting one of the avro files locally and displaying content with avro-tools"
docker container restart copy-files
docker container logs --tail=3 copy-files
docker run --rm -v /tmp:/tmp vdesabou/avro-tools tojson /tmp/minio_topic+0+0000000000.avro
