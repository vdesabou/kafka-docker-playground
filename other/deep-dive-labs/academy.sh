#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/academy: runs the reproduction models of the beginner exercises (academy/)
# and asserts the failure each exercise is about, then the fix the page gives. The intermediate exercise (S3 sink,
# StackOverflowError) needs an AWS account: not replayed here
lab_require_plaintext
academy="${DIR}/../../academy"

# the models fail on purpose (connector create-or-update stops at the FAILED task): their exit code is not checked
function run_model () {
    lab_run bash -c "cd '$academy/$1' && bash '$2'"
}

log "Exercise 1: Avro Converter: Unknown magic byte"
run_model connect-connect-filestream-sink filestream-sink-repro-000002-deserialization-error.sh
lab_run playground connector status --connector filestream-sink
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID"
lab_expect_contains "Caused by: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_run playground topic consume --topic filestream
lab_expect_contains "it contains 5 messages"
lab_expect_contains "|Partition:0|Offset:4|"
lab_expect_contains "1 record(s) of topic filestream could not be deserialized and were skipped"
lab_run playground consumer-group describe --group connect-filestream-sink
lab_expect_contains "Consumer group 'connect-filestream-sink' has no active members."

log "Exercise 1, Step 4: with a dead letter queue"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url": "http://schema-registry:8081",
     "errors.tolerance": "all",
     "errors.deadletterqueue.topic.name": "dlq",
     "errors.deadletterqueue.topic.replication.factor": "1",
     "errors.deadletterqueue.context.headers.enable": "true",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF
# no offset was committed: the task reads the topic from the beginning again
playground connector restart --connector filestream-sink
sleep 10
lab_run playground topic dlq inspect --topic dlq --no-open
lab_expect_contains "🔢 1 record(s) of connector filestream-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)"
lab_expect_contains "🌱 root cause: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_expect_contains "📍 original records: topic filestream partition 0 offsets 3..3 (1)"
lab_expect_contains '🔎 sample value: {"u_name": "poison pill", "u_price": 1.75, "u_quantity": 1}'
lab_run bash -c "docker exec connect cat /tmp/output.json | grep -c '^Struct{u_name='"
lab_expect_equals "$LAB_OUTPUT" "4" "valid records in the output file"

log "Exercise 2: InsertField SMT, sink connector"
run_model connect-connect-filestream-sink filestream-sink-repro-000003-insertfield-smt-dataexception-only-struct-objects-supported.sh
lab_run playground connector status --connector filestream-sink
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"
lab_run playground connector smt test --no-open --connector filestream-sink --from-topic filestream --offset 0
lab_expect_contains 'step 1  InsertField$Value "InsertField"'
lab_expect_contains "❌ org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"
lab_expect_contains "❌ the chain stopped at step 1"
chain_file=$(mktemp)
trap 'rm -f "$chain_file"' EXIT
cat > "$chain_file" << 'EOF'
{
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "transforms": "InsertField",
  "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.InsertField.static.field": "MessageSource",
  "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF
lab_run playground connector smt test --no-open --config @"$chain_file" --from-topic filestream --offset 0
lab_expect_contains '"MessageSource":"Kafka Connect framework"'
lab_expect_contains "✅ result: topic filestream, key null"

log "Exercise 2, Step 3: with a dead letter queue"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter",
     "transforms": "InsertField",
     "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertField.static.field": "MessageSource",
     "transforms.InsertField.static.value": "Kafka Connect framework",
     "errors.tolerance": "all",
     "errors.deadletterqueue.topic.name": "dlq",
     "errors.deadletterqueue.topic.replication.factor": "1",
     "errors.deadletterqueue.context.headers.enable": "true",
     "errors.log.enable": "true",
     "errors.log.include.messages": "true"
}
EOF
playground connector restart --connector filestream-sink
sleep 10
lab_run playground topic dlq inspect --topic dlq --no-open
lab_expect_contains "🔢 1 record(s) of connector filestream-sink, stage TRANSFORMATION (org.apache.kafka.connect.runtime.TransformationStage)"
lab_expect_contains "❌ org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"

log "Exercise 2, Steps 4 and 5: JsonConverter, then the topic, offset, partition and timestamp"
# like the page: the example runs again (a fresh environment), with the fixed config: the record of the model is processed
run_model connect-connect-filestream-sink filestream-sink-repro-000003-insertfield-smt-dataexception-only-struct-objects-supported.sh
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "transforms": "InsertField",
     "transforms.InsertField.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertField.static.field": "MessageSource",
     "transforms.InsertField.static.value": "Kafka Connect framework"
}
EOF
playground connector restart --connector filestream-sink
sleep 10
lab_run docker exec connect cat /tmp/output.json
lab_expect_contains "MessageSource=Kafka Connect framework"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false",
     "transforms": "InsertTopic,InsertOffset,InsertPartition,InsertTimestamp,TimestampConverter",
     "transforms.InsertOffset.offset.field": "__kafka_offset",
     "transforms.InsertOffset.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertPartition.partition.field": "__kafka_partition",
     "transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
     "transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.InsertTopic.topic.field": "__kafka_topic",
     "transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
     "transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
     "transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
     "transforms.TimestampConverter.target.type": "string",
     "transforms.TimestampConverter.field": "__kafka_ts"
}
EOF
playground topic produce -t filestream --nb-messages 1 << 'EOF'
{"customer_name":"Ed", "complaint_type":"Dirty car", "trip_cost": 29.10, "new_customer": false, "number_of_rides": 22}
EOF
sleep 10
lab_run docker exec connect tail -1 /tmp/output.json
lab_expect_contains "__kafka_topic=filestream, __kafka_partition=0"
lab_expect_contains "__kafka_offset=1"
lab_run bash -c "docker exec connect tail -1 /tmp/output.json | grep -oE '__kafka_ts=[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}'"
lab_expect_contains "__kafka_ts=" "__kafka_ts in the format yyyy-MM-dd HH:mm:ss.SSS"

log "Exercise 3: InsertField SMT, source connector"
run_model connect-connect-filestream-source filestream-source-repro-000004-insertfield-smt-dataexception-only-struct-objects-supported.sh
lab_run playground connector status --connector filestream-source
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.DataException: Only Struct objects supported for [field insertion], found: java.lang.String"
lab_run playground container logs -c connect --grep "Executing stage 'TRANSFORMATION'" --no-follow
lab_expect_contains "Executing stage 'TRANSFORMATION' with class 'org.apache.kafka.connect.runtime.TransformationStage'"
lab_expect_contains "valueSchema=Schema{STRING}"

log "Exercise 4: InsertField SMT, adding topic, offset and partition with a source connector"
run_model connect-connect-jdbc-mysql-source "mysql-repro-000005-insertfield-smt:-adding-topic-offset-and-partition-not-working.sh"
lab_run playground connector status --connector mysql-source
lab_expect_contains "0:🛑 FAILED"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.DataException: Only SinkRecord supported for [field insertion], found: org.apache.kafka.connect.source.SourceRecord"
lab_run playground connector smt test --no-open --connector mysql-source --record '{"topic":"mysql-team","value":{"id":102,"name":"another"}}'
lab_expect_contains "on a source record"
lab_expect_contains 'step 1  InsertField$Value "InsertTopic"'
lab_expect_contains 'step 2  InsertField$Value "InsertOffset"'
lab_expect_contains "❌ the chain stopped at step 2"
lab_run playground container logs -c connect --grep "Applying transformation" --no-follow
lab_expect_contains "Applying transformation org.apache.kafka.connect.transforms.InsertField\$Value to SourceRecord"
lab_expect_contains "__kafka_topic=mysql-team}"

log "Exercise 4, Steps 3 and 4: without InsertOffset, partition and timestamp are null"
playground connector create-or-update --connector mysql-source << 'EOF'
{
  "connector.class":"io.confluent.connect.jdbc.JdbcSourceConnector",
  "tasks.max":"1",
  "connection.url":"jdbc:mysql://mysql:3306/mydb?user=user&password=password&useSSL=false",
  "table.whitelist":"team",
  "mode":"timestamp+incrementing",
  "timestamp.column.name":"last_modified",
  "incrementing.column.name":"id",
  "topic.prefix":"mysql-",
  "errors.log.enable": "true",
  "errors.log.include.messages": "true",
  "transforms": "InsertTopic,InsertPartition,InsertTimestamp,TimestampConverter",
  "transforms.InsertPartition.partition.field": "__kafka_partition",
  "transforms.InsertPartition.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.InsertTimestamp.timestamp.field": "__kafka_ts",
  "transforms.InsertTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.InsertTopic.topic.field": "__kafka_topic",
  "transforms.InsertTopic.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.TimestampConverter.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
  "transforms.TimestampConverter.format": "yyyy-MM-dd HH:mm:ss.SSS",
  "transforms.TimestampConverter.target.type": "string",
  "transforms.TimestampConverter.field": "__kafka_ts"
}
EOF
playground connector restart --connector mysql-source
sleep 10
lab_run playground connector status --connector mysql-source
lab_expect_contains "0:🟢 RUNNING"
lab_run playground topic consume --topic mysql-team --max-messages 2
lab_expect_contains '"__kafka_topic":{"string":"mysql-team"},"__kafka_partition":null,"__kafka_ts":null'

log "✅ academy lab: the 4 beginner exercises behave as the page says"
