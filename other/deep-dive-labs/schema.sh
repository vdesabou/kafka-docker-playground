#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-schema
lab_require_plaintext
lab_start_environment

schema_dir=$(mktemp -d)
trap 'rm -rf "$schema_dir"' EXIT
cat > "$schema_dir/v1.avsc" << 'EOT'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"} ] }
EOT
cat > "$schema_dir/v2-bad.avsc" << 'EOT'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"}, {"name": "currency", "type": "string"} ] }
EOT
cat > "$schema_dir/v2.avsc" << 'EOT'
{ "type": "record", "name": "Order", "namespace": "com.example",
  "fields": [ {"name": "id", "type": "int"}, {"name": "amount", "type": "double"}, {"name": "currency", "type": "string", "default": "EUR"} ] }
EOT

log "Step 1: register, and register again"
lab_run playground schema register --subject orders-value < "$schema_dir/v1.avsc"
lab_expect_exit 0
lab_expect_contains "🔮 schema was identified as avro"
lab_expect_contains "⏺️ Registering schema to subject orders-value"
lab_expect_contains '"id": 1,'
lab_expect_contains '"version": 1,'
lab_run playground schema register --subject orders-value < "$schema_dir/v1.avsc"
lab_expect_exit 0
lab_expect_contains '"id": 1,'
lab_expect_contains '"version": 1,' "no new version"
lab_run playground schema get --subject orders-value
lab_expect_contains "🔰 subject orders-value 💯 version 1 (id 1)"
lab_run playground schema get --subject orders-value --schema-only
lab_expect_exit 0
lab_expect_contains '"name": "Order",'
lab_expect_not_contains "🔰 subject"
lab_run bash -c "playground schema get --subject orders-value --json | jq -r '.[0].id'"
lab_expect_equals "$LAB_OUTPUT" "1" "id of version 1 in --json"
lab_run playground schema list
lab_expect_exit 0
lab_expect_contains "SUBJECT"
lab_expect_contains "orders-value"

log "Step 2: compatibility refuses, then accepts"
lab_run playground schema get-compatibility --subject orders-value
lab_expect_exit 0
lab_expect_contains "🌍 subject orders-value has no subject-level rule: the global rule of the registry applies"
lab_expect_contains "BACKWARD"
lab_run bash -c "playground schema get-compatibility --subject orders-value --json | jq -r .source"
lab_expect_equals "$LAB_OUTPUT" "global" "source of the rule"
lab_run playground schema set-compatibility --subject orders-value --compatibility BACKWARD
lab_expect_contains "BACKWARD"
lab_expect_not_contains "null"
lab_run playground schema check-compatibility --subject orders-value < "$schema_dir/v2-bad.avsc"
lab_expect_exit 1
lab_expect_contains "❌ the schema is not compatible with the versions the rule checks of orders-value under BACKWARD (subject rule)"
lab_expect_contains "READER_FIELD_MISSING_DEFAULT_VALUE: The field 'currency'"
lab_run playground schema check-compatibility --subject orders-value --compatibility FORWARD < "$schema_dir/v2-bad.avsc"
lab_expect_exit 0
lab_expect_contains "✅ the schema is compatible"
lab_run playground schema diff --subject orders-value --to @"$schema_dir/v2-bad.avsc"
lab_expect_exit 0
lab_expect_contains "➕ currency: string"
lab_expect_contains "added without a default: the new schema can't read old data (breaks BACKWARD)"
lab_expect_contains "❌ BACKWARD"
lab_expect_contains "✅ FORWARD"
lab_run bash -c "playground schema list --json | jq -r '.subjects[].subject' | grep -c playground-schema-check || true"
lab_expect_equals "$LAB_OUTPUT" "0" "temporary subjects are deleted"
lab_run playground schema register --subject orders-value < "$schema_dir/v2-bad.avsc"
lab_expect_exit 1
lab_expect_contains '"error_code": 40901,'
lab_expect_contains "READER_FIELD_MISSING_DEFAULT_VALUE"
lab_expect_contains "❌ schema registry refused the schema for subject orders-value (error code 40901)"
lab_run playground schema register --subject orders-value < "$schema_dir/v2.avsc"
lab_expect_exit 0
lab_expect_contains '"id": 2,'
lab_expect_contains '"version": 2,'

log "Step 3: records, then a soft delete"
playground topic produce -t orders --nb-messages 2 < "$schema_dir/v2.avsc"
lab_run playground topic consume -t orders --min-expected-messages 2 --timeout 60
lab_expect_exit 0
lab_expect_contains "topic is using avro for value"
lab_expect_contains "|ValueSchemaId:2"
lab_run playground schema delete --subject orders-value
lab_expect_contains "🧟 Soft deleting subject 🔰 orders-value"
lab_run playground schema get --subject orders-value
lab_expect_exit 1
lab_expect_contains "❌ No schema found !"
lab_run playground schema get --deleted
lab_expect_contains "🧟 (deleted) subject orders-value 💯 version 1 (id 1)"
lab_expect_contains "🧟 (deleted) subject orders-value 💯 version 2 (id 2)"
lab_run playground schema get --id 2
lab_expect_exit 0
lab_expect_contains '"subject": "orders-value",'
lab_expect_contains '"deleted": true'
lab_run playground topic consume -t orders --min-expected-messages 2 --timeout 60
lab_expect_contains "topic is not using any schema for value" "topic consume finds no subject after a soft delete"

lab_run playground schema describe --id 2
lab_expect_exit 0
lab_expect_contains "💯 schema id 2: AVRO com.example.Order"
lab_expect_contains "🔰 orders-value v2 🧟 soft deleted"

log "Step 3b: re-register after a soft delete: same id, next version"
lab_run playground schema register --subject orders-value < "$schema_dir/v2.avsc"
lab_expect_exit 0
lab_expect_contains '"id": 2,'
lab_expect_contains '"version": 3,'

log "Step 4: a permanent delete"
lab_run playground schema delete --subject orders-value --version 9
lab_expect_exit 1
lab_expect_contains "❌ subject orders-value has no version 9"
lab_run playground schema delete --subject orders-value --permanent --dry-run
lab_expect_exit 0
lab_expect_contains "💀 version 3 (id 2): permanent delete, ❌ id 2 will stop resolving"
lab_run playground schema get --id 2
lab_expect_exit 0 "a dry run deletes nothing"
lab_run playground schema delete --subject orders-value --permanent
lab_expect_contains "💀 Hard deleting subject 🔰 orders-value"
lab_run playground schema get --id 2
lab_expect_exit 1
lab_expect_contains "Command failed with error code 40403"
lab_expect_contains "Schema 2 not found"
lab_run playground schema register --subject orders-value < "$schema_dir/v1.avsc"
lab_expect_exit 0
lab_expect_contains '"version": 1,'
new_id=$(grep -oE '"id": [0-9]+' <<< "$LAB_OUTPUT" | head -1 | grep -oE '[0-9]+')
if [ "$new_id" == "2" ] || [ "$new_id" == "" ]
then
    logerror "❌ expected a new id after a permanent delete, got '$new_id'"
    exit 1
fi
log "✅ new id $new_id after a permanent delete"

log "Step 4b: export and import keep the ids"
lab_run playground schema export -o "$schema_dir/export"
lab_expect_exit 0
lab_expect_contains "exported to $schema_dir/export"
lab_run playground schema delete --subject orders-value --permanent
lab_expect_exit 0
lab_run playground schema import -f "$schema_dir/export"
lab_expect_exit 0
lab_expect_contains "➕ orders-value: v1 id $new_id"
lab_expect_contains "imported with their ids"
lab_run playground schema get --id "$new_id" --schema-only
lab_expect_exit 0
lab_expect_contains '"name": "Order",'

lab_run playground schema history --subject orders-value
lab_expect_exit 0
lab_expect_contains "⏺️ orders-value: registered v1 (id 1, AVRO)"
lab_expect_contains "🧟 orders-value: soft deleted the subject (versions 1, 2): the ids still resolve"
lab_expect_contains "❌ id 1 no longer resolves"
lab_expect_contains "ids that no longer resolve: 1, 2"
lab_run playground schema describe --subject orders-value
lab_expect_exit 0
lab_expect_contains "🧭 strategy       TopicNameStrategy → topic orders ✅"

log "Step 5: derive a schema"
lab_run playground schema derive-schema << 'EOT'
{"order_id": 1, "customer": "acme", "amount": 9.99}
{"order_id": 2, "customer": "globex", "amount": 12}
EOT
lab_expect_exit 0
lab_expect_contains "🪄 Schema file generated"
lab_expect_contains '"type": "record",'
lab_expect_contains '"name": "order_id",'
lab_expect_contains '"name": "customer",'
lab_expect_contains '"name": "amount",'
lab_run playground schema derive-schema --schema-type PROTOBUF --payload '{"sport": "Football"}'
lab_expect_exit 0
lab_expect_contains 'syntax = "proto3";'
lab_expect_contains "message Schema {"
lab_expect_contains "string sport = 1;"

log "✅ all the outputs of the page are as expected"
