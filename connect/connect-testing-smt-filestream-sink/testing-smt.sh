#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh

PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}
playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"

# log "✂️ Setting up Jscissors to intercept the transformation chain in Connect framework"
# playground debug jscissors --class 'org.apache.kafka.connect.runtime.TransformationChain' --method "apply" --operation VALUES --operation RETURN_VALUE

log "Sending messages to topic filestream"
playground topic produce -t filestream --nb-messages 1 << 'EOF'
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

    "transforms": "InsertMeta,AddGroup,AddLoadTime,WrapPayload",
    "transforms.AddGroup.static.field": "group_name",
    "transforms.AddGroup.static.value": "my group",
    "transforms.AddGroup.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
    "transforms.AddLoadTime.timestamp.field": "kafka_datetime",
    "transforms.AddLoadTime.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
    "transforms.InsertMeta.offset.field": "offset_value",
    "transforms.InsertMeta.partition.field": "partition_id",
    "transforms.InsertMeta.topic.field": "topic_name",
    "transforms.InsertMeta.type": "org.apache.kafka.connect.transforms.InsertField\$Value",
    "transforms.WrapPayload.field": "payload",
    "transforms.WrapPayload.type": "org.apache.kafka.connect.transforms.HoistField\$Value"
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

# Struct{payload=Struct{count=1,first_name=Mateo,last_name=Karolann,address=Oscar,topic_name=filestream,partition_id=0,offset_value=0,group_name=my group,kafka_datetime=Fri Mar 27 14:09:22 GMT 2026}}

playground container logs --container connect  --wait-for-log "Applying transformation "