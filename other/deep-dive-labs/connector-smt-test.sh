#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-connector-smt-test
lab_require_plaintext
lab_start_environment
lab_create_filestream_sink

chain_file=$(mktemp)
trap 'rm -f "$chain_file"' EXIT
cat > "$chain_file" << 'JSON'
{
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "transforms": "AddGroup,Route",
  "transforms.AddGroup.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.AddGroup.static.field": "group_name",
  "transforms.AddGroup.static.value": "my group",
  "transforms.Route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.Route.regex": "(.*)",
  "transforms.Route.replacement": "$1-copy"
}
JSON

log "Step 1: a chain on stdin, on a record of your own"
lab_run playground connector smt test --no-open --record '{"topic":"filestream","key":"k1","value":{"id":1,"name":"foo"}}' < "$chain_file"
lab_expect_exit 0
lab_expect_contains "🧪 2 transform(s) on a sink record"
lab_expect_contains 'step 1  InsertField$Value "AddGroup"'
lab_expect_contains '"group_name":"my group"'
lab_expect_contains 'step 2  RegexRouter "Route"'
lab_expect_contains "filestream → filestream-copy"
lab_expect_contains '✅ result: topic filestream-copy, key "k1"'
lab_expect_contains "📊 report: /tmp/playground-smt-test/"

log "Step 2: a real record of the topic, through the converters"
lab_run playground connector smt test --no-open --config @"$chain_file" --from-topic filestream --offset 0
lab_expect_exit 0
lab_expect_contains "topic     filestream  partition 0  offset 0"
lab_expect_contains '"name":"name-1"'
lab_expect_contains "schema    schemaless"
lab_expect_contains "✅ result: topic filestream-copy, key null"

log "Step 3: the chain of a running connector"
playground connector create-or-update -c filestream-sink << 'JSON'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "transforms": "AddGroup,Filter",
  "transforms.AddGroup.type": "org.apache.kafka.connect.transforms.InsertField$Value",
  "transforms.AddGroup.static.field": "group_name",
  "transforms.AddGroup.static.value": "my group",
  "transforms.Filter.type": "org.apache.kafka.connect.transforms.Filter",
  "transforms.Filter.predicate": "IsFilestream",
  "transforms.Filter.negate": "true",
  "predicates": "IsFilestream",
  "predicates.IsFilestream.type": "org.apache.kafka.connect.transforms.predicates.TopicNameMatches",
  "predicates.IsFilestream.pattern": "filestream"
}
JSON
lab_run playground connector smt test --no-open --connector filestream-sink --from-topic filestream --offset 1
lab_expect_exit 0
lab_expect_contains 'step 2  Filter "Filter"'
lab_expect_contains "predicate IsFilestream (TopicNameMatches) = true, negate=true"
lab_expect_contains "⏭️ skipped (predicate)"
lab_expect_contains "✅ result: topic filestream, key null"
lab_run playground connector smt test --no-open --connector filestream-sink --record '{"topic":"other","value":{"id":1}}'
lab_expect_exit 0
lab_expect_contains "predicate IsFilestream (TopicNameMatches) = false, negate=true"
lab_expect_contains "🗑️ the record is dropped (the transform returned null)"
lab_expect_contains "🗑️ dropped by step 2"

log "Step 4: a field added as null, then a failing step"
lab_run playground connector smt test --no-open --record '{"topic":"t","value":{"id":1,"name":"foo"}}' << 'JSON'
{
  "transforms": "Ts,Cast",
  "transforms.Ts.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
  "transforms.Ts.field": "created_at",
  "transforms.Ts.target.type": "Timestamp",
  "transforms.Cast.type": "org.apache.kafka.connect.transforms.Cast$Value",
  "transforms.Cast.spec": "name:int32"
}
JSON
lab_expect_exit 1
lab_expect_contains '"created_at":null' "TimestampConverter adds the missing field as null"
lab_expect_contains "org.apache.kafka.connect.errors.DataException: Value (foo) was out of range for requested data type"
lab_expect_contains 'java.lang.NumberFormatException: For input string: "foo"'
lab_expect_contains "❌ the chain stopped at step 2 (--verbose or --json for the stack trace)"
lab_run playground connector smt test --no-open --record '{"topic":"t","value":{"id":1,"name":"foo"}}' \
  --config '{"transforms":"Drop","transforms.Drop.type":"org.apache.kafka.connect.transforms.ReplaceField$Value","transforms.Drop.exclude":"nme"}'
lab_expect_exit 0
lab_expect_contains 'step 1  ReplaceField$Value "Drop"  (exclude=nme)'
lab_expect_contains "(no change)"

log "Step 5: two CP versions, and JSON"
lab_run playground connector smt test --no-open --config @"$chain_file" --record '{"topic":"filestream","value":{"id":1}}' --cp-version 7.9.0 --cp-version 8.3.2
lab_expect_exit 0
lab_expect_contains "🔢 CP 7.9.0: throwaway confluentinc/cp-server-connect:7.9.0"
lab_expect_contains "⚖️ final result per CP version"
lab_expect_contains 'CP 7.9.0 (Kafka 7.9.0-ce): topic filestream-copy, key null, value {"group_name":"my group","id":1}'
lab_expect_contains 'CP 8.3.2 (Kafka 8.3.2-ce): topic filestream-copy, key null, value {"group_name":"my group","id":1}'
lab_expect_contains "✅ same result with all the CP versions"
lab_run bash -c "playground connector smt test --config @$chain_file --record '{\"topic\":\"filestream\",\"value\":{\"id\":1}}' --json 2>/dev/null | jq -c '.steps[] | {index, alias, topic: .record.topic}'"
lab_expect_exit 0
lab_expect_contains '{"index":0,"alias":"input","topic":"filestream"}'
lab_expect_contains '{"index":1,"alias":"AddGroup","topic":"filestream"}'
lab_expect_contains '{"index":2,"alias":"Route","topic":"filestream-copy"}'

log "✅ all the outputs of the page are as expected"
