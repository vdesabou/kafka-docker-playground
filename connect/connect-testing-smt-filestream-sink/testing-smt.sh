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

log "Waiting for the record in the output file"
for i in $(seq 1 30)
do
    if playground container exec --container connect --command "cat /tmp/output.json" 2> /dev/null | grep -q "payload"
    then
        break
    fi
    sleep 2
done
playground container exec --container connect --command "cat /tmp/output.json"
# Struct{payload=Struct{count=1,first_name=Mateo,last_name=Karolann,address=Oscar,topic_name=filestream,partition_id=0,offset_value=0,group_name=my group,kafka_datetime=Fri Mar 27 14:09:22 GMT 2026}}

#######
# 🧪 playground connector smt test: what a transform chain does to a record, step by step, in a few seconds,
# without creating a connector or producing a record. Each run prints the steps and writes an html report in
# /tmp/playground-smt-test/ (--no-open: only the last one is opened in the browser)
#######

log "🧪 1/11 the transforms of the running connector, on a default record"
playground connector smt test --connector filestream-sink --no-open

log "🧪 2/11 the transforms of the running connector, on the real record of its topic (read and converted with its AvroConverter and Schema Registry)"
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0 --no-open

log "🧪 3/11 the transforms of the running connector, on your own record"
playground connector smt test --connector filestream-sink --record '{"topic":"filestream","key":"k1","value":{"count":2,"first_name":"Jane"}}' --no-open

log "🧪 4/11 a transform chain on stdin, with typed headers (duplicate keys with the array form), predicates and negate"
playground connector smt test --no-open --record '{"topic":"orders","key":"o-1","value":{"id":1,"tenant":"acme","amount":10},"headers":[{"key":"source","value":"crm"},{"key":"retries","value":3},{"key":"trace","value":"a"},{"key":"trace","value":"b"}]}' << 'EOF'
{
  "transforms": "addVersion,tenantToHeader,dropTrace,defaultSource,markCrm,route",
  "predicates": "hasSource",
  "predicates.hasSource.type": "org.apache.kafka.connect.transforms.predicates.HasHeaderKey",
  "predicates.hasSource.name": "source",

  "transforms.addVersion.type": "org.apache.kafka.connect.transforms.InsertHeader",
  "transforms.addVersion.header": "schema_version",
  "transforms.addVersion.value.literal": "2",

  "transforms.tenantToHeader.type": "org.apache.kafka.connect.transforms.HeaderFrom$Value",
  "transforms.tenantToHeader.fields": "tenant",
  "transforms.tenantToHeader.headers": "tenant",
  "transforms.tenantToHeader.operation": "move",

  "transforms.dropTrace.type": "org.apache.kafka.connect.transforms.DropHeaders",
  "transforms.dropTrace.headers": "trace",

  "transforms.defaultSource.type": "org.apache.kafka.connect.transforms.InsertHeader",
  "transforms.defaultSource.header": "source",
  "transforms.defaultSource.value.literal": "unknown",
  "transforms.defaultSource.predicate": "hasSource",
  "transforms.defaultSource.negate": "true",

  "transforms.markCrm.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.markCrm.static.field": "from_crm",
  "transforms.markCrm.static.value": "yes",
  "transforms.markCrm.predicate": "hasSource",

  "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.route.regex": "(.*)",
  "transforms.route.replacement": "crm-$1"
}
EOF

log "🧪 5/11 the transforms and the record in files (--config @file, --record @file), on a value with a schema (Struct): Cast, ReplaceField, TimestampConverter, SetSchemaMetadata"
playground connector smt test --config @${DIR}/smt-test/transforms-struct.json --record @${DIR}/smt-test/record-struct.json --no-open

log "🧪 6/11 a dropped record: Filter with the RecordIsTombstone predicate on a tombstone (the next transforms do not run)"
playground connector smt test --no-open --record '{"topic":"orders","key":"o-1","value":null}' << 'EOF'
{
  "transforms": "dropTombstones,addField",
  "predicates": "isTombstone",
  "predicates.isTombstone.type": "org.apache.kafka.connect.transforms.predicates.RecordIsTombstone",
  "transforms.dropTombstones.type": "org.apache.kafka.connect.transforms.Filter",
  "transforms.dropTombstones.predicate": "isTombstone",
  "transforms.addField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.addField.static.field": "never",
  "transforms.addField.static.value": "applied"
}
EOF

log "🧪 7/11 a failing transform (exit code 1): InsertField offset.field only works on a sink record, here on a source record (--type source)"
set +e
playground connector smt test --type source --no-open --record '{"topic":"orders","value":{"id":1}}' << 'EOF'
{
  "transforms": "addOffset",
  "transforms.addOffset.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.addOffset.offset.field": "kafka_offset"
}
EOF
ret=$?
set -e
if [ $ret -ne 1 ]
then
    logerror "❌ expected exit code 1 for a failing transform, got $ret"
    exit 1
fi
log "✅ the failing transform is reported with its config and its error, exit code 1"

log "🧪 8/11 SMTs from plugins of the worker: Confluent connect-transforms (ExtractTopic) and jcustenborder transform-common (ChangeCase)"
playground connector smt test --record @${DIR}/smt-test/record-struct.json --no-open << 'EOF'
{
  "transforms": "camelCase,topicFromField",
  "transforms.camelCase.type": "com.github.jcustenborder.kafka.connect.transform.common.ChangeCase$Value",
  "transforms.camelCase.from": "LOWER_UNDERSCORE",
  "transforms.camelCase.to": "LOWER_CAMEL",
  "transforms.topicFromField.type": "io.confluent.connect.transforms.ExtractTopic$Value",
  "transforms.topicFromField.field": "firstName"
}
EOF

log "🧪 9/11 another version of an SMT plugin, installed from Confluent Hub for the test only (--smt-plugin), and a jar with its dependencies (--smt-jar, e.g. your own build): they are used instead of the copy of the worker"
playground connector smt test --record @${DIR}/smt-test/record-struct.json --smt-plugin confluentinc/connect-transforms:1.4.4 --no-open << 'EOF'
{
  "transforms": "topicFromField",
  "transforms.topicFromField.type": "io.confluent.connect.transforms.ExtractTopic$Value",
  "transforms.topicFromField.field": "first_name"
}
EOF
playground connector smt test --record @${DIR}/smt-test/record-struct.json --no-open \
    --smt-jar ${DIR}/../../confluent-hub/jcustenborder-kafka-connect-transform-common/lib/kafka-connect-transform-common-0.2.5.jar \
    --smt-jar ${DIR}/../../confluent-hub/jcustenborder-kafka-connect-transform-common/lib/connect-utils-0.8.0.jar << 'EOF'
{
  "transforms": "camelCase",
  "transforms.camelCase.type": "com.github.jcustenborder.kafka.connect.transform.common.ChangeCase$Value",
  "transforms.camelCase.from": "LOWER_UNDERSCORE",
  "transforms.camelCase.to": "LOWER_CAMEL"
}
EOF

log "🧪 10/11 --json for scripts: assert the final record with jq"
result=$(playground connector smt test --json --config @${DIR}/smt-test/transforms-struct.json --record @${DIR}/smt-test/record-struct.json)
final=$(echo "$result" | jq -c '[.steps[] | select(.record)] | last | .record')
echo "$final" | jq .
if echo "$final" | jq -e '(.value | fromjson) as $v | $v.email_address == "john@example.com" and $v.created_at == "2025-10-09" and (.value_schema | startswith("com.acme.Customer v2:"))' > /dev/null
then
    log "✅ email renamed, date formatted, schema name and version set as expected"
else
    logerror "❌ unexpected final record"
    exit 1
fi

log "🧪 11/11 would the transforms of the connector behave the same on another CP version? (--cp-version, in throwaway cp-server-connect containers)"
playground connector smt test --connector filestream-sink --from-topic filestream --offset 0 --cp-version 7.9.0 --cp-version ${TAG}
