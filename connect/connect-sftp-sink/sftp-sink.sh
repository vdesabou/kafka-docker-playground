#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

if version_gt $TAG_BASE "7.9.99" && ! version_gt $CONNECTOR_TAG "3.1.99"
then
     logwarn "minimal supported connector version is 3.2.0 for CP 8.0"
     logwarn "see https://docs.confluent.io/platform/current/connect/supported-connector-version-8.0.html#supported-connector-versions-in-cp-8-0"
     exit 111
fi

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Creating SFTP Sink connector"
playground connector create-or-update --connector sftp-sink  << EOF
{
  "topics": "test_sftp_sink",
  "tasks.max": "1",
  "connector.class": "io.confluent.connect.sftp.SftpSinkConnector",
  "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
  "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
  "flush.size": "3",
  "schema.compatibility": "NONE",
  "format.class": "io.confluent.connect.sftp.sink.format.avro.AvroFormat",
  "storage.class": "io.confluent.connect.sftp.sink.storage.SftpSinkStorage",
  "sftp.host": "sftp-server",
  "sftp.port": "22",
  "sftp.username": "foo",
  "sftp.password": "pass",
  "sftp.working.dir": "/upload",
  "confluent.license": "",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1"
}
EOF


log "Sending messages to topic test_sftp_sink"
playground topic produce -t test_sftp_sink --nb-messages 10 --forced-value '{"f1":"value%g"}' << 'EOF'
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

log "Listing content of ./upload/topics/test_sftp_sink/partition\=0/"
docker exec sftp-server bash -c "ls /home/foo/upload/topics/test_sftp_sink/partition\=0/"

docker cp sftp-server:/home/foo/upload/topics/test_sftp_sink/partition\=0/test_sftp_sink+0+0000000000.avro /tmp/

playground  tools read-avro-file --file /tmp/test_sftp_sink+0+0000000000.avro