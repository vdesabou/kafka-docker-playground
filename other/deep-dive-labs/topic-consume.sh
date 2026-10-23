#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-topic-consume

schemas="${DIR}/../../scripts/cli/predefined-schemas"
playground_cli="${DIR}/../../scripts/cli/playground"

lab_require_plaintext
lab_start_environment
playground topic produce -t orders --nb-messages 5 --key 'order-%g' --nb-partitions 3 < "$schemas/avro/customer.avsc"
playground topic produce -t ticks --nb-messages 10 --value '{"tick": %g}'

log "Step 1: default order and positioning"
lab_run playground topic consume -t orders
lab_expect_exit 0
lab_expect_contains "✨ Display content of topic orders, it contains 5 messages"
lab_expect_contains "🔮🔰 topic is using avro for value"
# the key decides the partition (murmur2): order-2 and order-3 in 0, order-1 in 1, order-4 and order-5 in 2
lab_expect_contains "Partition:0|Offset:0|Headers:NO_HEADERS|Key:order-2|"
lab_expect_contains "Partition:0|Offset:1|Headers:NO_HEADERS|Key:order-3|"
lab_expect_contains "Partition:1|Offset:0|Headers:NO_HEADERS|Key:order-1|"
lab_expect_contains "Partition:2|Offset:0|Headers:NO_HEADERS|Key:order-4|"
lab_expect_contains "Partition:2|Offset:1|Headers:NO_HEADERS|Key:order-5|"
first_partition=$(grep -m1 "^CreateTime:" <<< "$LAB_OUTPUT" | sed -E 's/.*\|Partition:([0-9]+)\|.*/\1/')
lab_expect_equals "$first_partition" "0" "partition of the first record displayed (partition by partition, not time)"
lab_run playground topic consume -t orders --last 2 --max-characters 90
lab_expect_exit 0
lab_expect_contains "⏮️ Display the last 2 records of topic orders"
lab_expect_equals "$(grep -c "^CreateTime:" <<< "$LAB_OUTPUT")" "2" "records displayed with --last 2"
lab_expect_contains "...<truncated, only showing first 90 characters"
lab_run playground topic consume -t orders --partition 2 --offset 1 --max-messages 1
lab_expect_exit 0
lab_expect_contains "🧭 Display records of topic orders, partition 2, from offset 1"
lab_expect_contains "Partition:2|Offset:1|Headers:NO_HEADERS|Key:order-5|"

log "Step 2: assertions that fail"
lab_run playground topic consume -t ticks --min-expected-messages 20 --timeout 5
lab_expect_exit 1
lab_expect_contains "❌ overall timeout of 5 seconds exceeded. --min-expected-messages is set with 20 but topic ticks contains 10 messages"
lab_run playground topic consume -t ticks --grep '"tick": 7' --count
lab_expect_exit 0
lab_expect_contains '✅ found "tick": 7 in 1 record(s) of topic ticks'
lab_expect_equals "$(echo "$LAB_OUTPUT" | tail -1)" "1" "--grep --count"

log "Step 3: offsets are not records"
playground topic produce -t orders --value 'not avro' --value-format raw
lab_run playground topic consume -t orders --min-expected-messages 6
lab_expect_exit 1
lab_expect_contains "⚠️ 1 record(s) of topic orders could not be deserialized and were skipped, first error: org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID (caused by: java.lang.IllegalArgumentException: Unknown magic byte!)"
lab_expect_contains "❌ --min-expected-messages is set with 6 but only 5 records could be consumed from topic orders (6 offsets, 1 could not be deserialized)"

log "Step 4: a subject that doesn't follow the topic name"
playground topic produce -t events --nb-messages 1 --value-subject-name-strategy TopicRecordNameStrategy < "$schemas/avro/customer.avsc"
lab_run playground topic consume -t events
lab_expect_exit 0
lab_expect_contains "🔮🙅 topic is not using any schema for value"
lab_expect_not_contains "ValueSchemaId:" "schema id without the subject"
lab_run playground topic consume -t events --value-subject events-com.github.vdesabou.Customer
lab_expect_exit 0
lab_expect_contains "📛 value subject is set with events-com.github.vdesabou.Customer"
lab_expect_contains '|Value:{"count":1,"first_name":'
lab_expect_contains "|ValueSchemaId:"

log "Step 5: base64, tombstone, tail"
playground topic produce -t b64 --value 'eyJpZCI6IDF9'
lab_run playground topic consume -t b64
lab_expect_exit 0
lab_expect_contains "🤖 Data is base64 encoded, payload will be decoded"
lab_expect_contains 'Value:{"id": 1}'
lab_run playground topic consume -t b64 --no-decode
lab_expect_exit 0
lab_expect_contains "Value:eyJpZCI6IDF9"
playground topic produce -t ticks --tombstone --key k1
lab_run playground topic consume -t ticks --last 1
lab_expect_exit 0
lab_expect_contains "Key:k1|Value:null"
# the page produces from another terminal: a background producer here, and --tail stopped by timeout
lab_run bash -c "(sleep 8; $playground_cli topic produce -t ticks --value 'live-%g' --nb-messages 2 > /dev/null 2>&1) & timeout 30 $playground_cli topic consume -t ticks --tail"
lab_expect_exit 124
lab_expect_contains "✨ Tailing content of topic ticks"
lab_expect_contains "Value:live-1"
lab_expect_contains "Value:live-2"
lab_expect_not_contains 'Value:{"tick": 1}' "old records with --tail"

log "✅ all the outputs of the page are as expected"
