#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-topic-administration
lab_require_plaintext
lab_start_environment

log "Step 1: create, and create again"
lab_run playground topic create -t lab-orders --nb-partitions 3 --config retention.ms=600000
lab_expect_exit 0
lab_expect_contains "🆕 Creating topic lab-orders"
lab_run playground topic create -t lab-orders
lab_expect_exit 1
lab_expect_contains "❌ topic lab-orders already exist !"

log "Step 2: what the topic looks like"
lab_run playground topic describe -t lab-orders
lab_expect_contains "🔎 Describing topic lab-orders"
lab_expect_contains "PartitionCount: 3"
lab_expect_contains "ReplicationFactor: 1"
lab_expect_contains "retention.ms=600000"
lab_run playground topic create -t connect-lab --nb-partitions 1
lab_expect_exit 0
lab_run playground topic list
lab_expect_contains "🔘 List of topics (internal topics are excluded)"
lab_expect_contains "lab-orders"
lab_expect_not_contains "connect-lab" "a connect-… topic is hidden like an internal one"
lab_run playground topic list --show-internal
lab_expect_contains "🫥 List of topics (internal topics are included)"
lab_expect_contains "connect-lab"
lab_expect_contains "_schemas"

log "Step 3: records, counts and offsets"
lab_run playground topic produce -t lab-orders --nb-messages 10 --key 'k%g' --value '{"id": %g}'
lab_expect_exit 0
lab_run playground topic get-number-records -t lab-orders
lab_expect_contains "💯 Get number of records in topic lab-orders"
lab_expect_equals "$(grep -E '^[0-9]+$' <<< "$LAB_OUTPUT" | tail -1)" "10" "records in lab-orders"
lab_run playground topic get-offsets -t lab-orders
lab_expect_contains "📍 Earliest and latest offsets per partition of topic lab-orders"
lab_expect_contains "PARTITION EARLIEST LATEST RECORDS"
lab_expect_equals "$(awk '$1 == "TOTAL" {print $2}' <<< "$LAB_OUTPUT")" "10" "TOTAL of get-offsets"
lab_run playground topic get-size -t lab-orders
lab_expect_contains "SIZE PARTITIONS TOPIC"
lab_expect_equals "$(awk '$1 ~ /^[0-9.]+$/ && $NF == "lab-orders" {print $(NF-1)}' <<< "$LAB_OUTPUT")" "3" "partitions in get-size"

log "Step 4: a config that breaks a producer, then back"
lab_run playground topic alter -t lab-orders --add-config max.message.bytes=1000
lab_expect_exit 0
lab_expect_contains "🪛 Altering topic lab-orders"
lab_run playground topic describe -t lab-orders
lab_expect_contains "max.message.bytes=1000"
lab_run playground topic produce -t lab-orders --nb-messages 1 --record-size 5000 < "${DIR}/../../scripts/cli/predefined-schemas/avro/lead.avsc"
lab_expect_contains "RecordTooLarge" "the broker refuses a record bigger than max.message.bytes"
lab_run playground topic alter -t lab-orders --delete-config max.message.bytes
lab_expect_exit 0
lab_run playground topic describe -t lab-orders
lab_expect_not_contains "max.message.bytes=1000" "the override is gone"
lab_run playground topic alter -t lab-created-by-alter --add-config retention.ms=60000
lab_expect_contains "🆕 topic lab-created-by-alter does not exist, creating it..."

log "Step 5: waiting for records that come, and records that don't"
lab_run playground topic wait-for-records -t lab-later --min-expected-messages 1 --max-wait 10
lab_expect_exit 1
lab_expect_contains "⏳ Waiting up to 10 seconds for topic lab-later to contain at least 1 records"
lab_expect_contains "❌ topic lab-later contains 0 records after 10 seconds, expected at least 1"
(sleep 5; ${DIR}/../../scripts/cli/playground topic produce -t lab-later --nb-messages 3 --value 'x%g' > /dev/null 2>&1) &
lab_run playground topic wait-for-records -t lab-later --min-expected-messages 3 --max-wait 60
lab_expect_exit 0
lab_expect_contains "✅ topic lab-later contains 3 records (expected at least 3)"
wait

log "Step 6: delete, subjects included"
lab_run playground topic produce -t lab-avro --nb-messages 2 < "${DIR}/../../scripts/cli/predefined-schemas/avro/customer.avsc"
lab_expect_exit 0
lab_run playground schema get --subject lab-avro-value
lab_expect_contains "🔰 subject lab-avro-value"
lab_run playground topic delete -t lab-avro
lab_expect_exit 0
lab_expect_contains "❌ Deleting topic lab-avro"
lab_expect_contains "🔰 Delete subject lab-avro-value"
lab_run playground schema get --subject lab-avro-value
lab_expect_exit 1
lab_expect_contains "❌ No schema found !"
lab_run playground topic delete -t 'lab-.*'
lab_expect_contains "✨ --topic is treated as regex. Matching topics:"
lab_expect_contains "lab-later"
lab_expect_contains "lab-orders"
lab_run playground topic delete -t lab-nope
lab_expect_exit 0
lab_expect_contains "❌ topic lab-nope does not exist and regex does not match any topic !"

log "✅ all the outputs of the page are as expected"
