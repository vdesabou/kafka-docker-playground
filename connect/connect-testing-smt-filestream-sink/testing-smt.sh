#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

log "Sending messages to topic filestream"
playground topic produce -t filestream --nb-messages 5 << 'EOF'
{
  "fields": [
    {
      "doc": "count",
      "name": "count",
      "type": "long"
    },
    {
      "doc": "First Name of Customer",
      "name": "first_name",
      "type": "string"
    },
    {
      "doc": "Last Name of Customer",
      "name": "last_name",
      "type": "string"
    },
    {
      "doc": "Address of Customer",
      "name": "address",
      "type": "string"
    }
  ],
  "name": "Customer",
  "namespace": "com.github.vdesabou",
  "type": "record"
}
EOF

playground debug log-level set -p "org.apache.kafka.connect.runtime.WorkerSinkTask" -l TRACE
playground debug log-level set -p "org.apache.kafka.connect.runtime.TransformationChain" -l TRACE

log "Creating FileStream Sink connector"
playground connector create-or-update --connector filestream-sink  << EOF
{
    "tasks.max": "1",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "filestream",
    "file": "/tmp/output.json",

    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081",

    "transforms": "InsertField",
    "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
    "transforms.InsertField.static.field": "MessageSource",
    "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF

    # "value.converter": "io.confluent.connect.json.JsonSchemaConverter",
    # "value.converter.schema.registry.url": "http://schema-registry:8081",

    # "value.converter": "io.confluent.connect.protobuf.ProtobufConverter",
    # "value.converter.schema.registry.url": "http://schema-registry:8081",

    # "value.converter":"org.apache.kafka.connect.json.JsonConverter",
    # "value.converter.schemas.enable":"false",

sleep 5

log "Verify we have received the data in file"
docker exec connect cat /tmp/output.json

# Struct{count=1,first_name=Nola,last_name=Prudence,address=Brandon,MessageSource=Kafka Connect framework}
# Struct{count=2,first_name=Blanca,last_name=Bethany,address=Yoshiko,MessageSource=Kafka Connect framework}
# Struct{count=3,first_name=Lilla,last_name=Jermaine,address=Manuel,MessageSource=Kafka Connect framework}
# Struct{count=4,first_name=Bret,last_name=Kiana,address=Reyna,MessageSource=Kafka Connect framework}
# Struct{count=5,first_name=George,last_name=Braeden,address=Karolann,MessageSource=Kafka Connect framework}