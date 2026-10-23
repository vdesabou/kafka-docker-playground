#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-connector-troubleshooting
lab_require_plaintext
lab_start_environment

log "Setup: an Avro topic that also contains two plain JSON records"
playground topic produce -t orders --nb-messages 3 < ${DIR}/../../scripts/cli/predefined-schemas/avro/customer.avsc
playground topic produce -t orders --nb-messages 2 --value '{"id": %g}'

log "Step 1: the default is a loud failure"
playground connector create-or-update --connector strict-sink --no-wait << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "orders",
  "file": "/tmp/strict.txt",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
playground connector wait --connector strict-sink --state FAILED --max-wait 60
lab_run playground connector diagnose --connector strict-sink --since 5m --max-findings 3
lab_expect_exit 0
lab_expect_contains "1/4 status"
lab_expect_contains "ConnectException: Tolerance exceeded in error handler"
lab_expect_contains "Caused by: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_expect_contains "2/4 errors: digest of connect ERROR/FATAL records since 5m (whole worker, not only this connector)"
lab_expect_contains "WorkerSinkTask{id=strict-sink-0} Task threw an uncaught and unrecoverable exception"
lab_expect_contains "3/4 progress: committed offsets of sink strict-sink (no lag while the connector and all its tasks are not RUNNING)"
lab_expect_contains '"offsets": []'
lab_expect_contains "a task or the connector FAILED"
lab_expect_contains "playground connector restart --connector strict-sink"
playground connector delete --connector strict-sink

log "Step 2: errors.tolerance=all, a silent one"
playground connector create-or-update --connector orders-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "orders",
  "file": "/tmp/orders.txt",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081",
  "errors.tolerance": "all",
  "errors.deadletterqueue.topic.name": "dlq",
  "errors.deadletterqueue.topic.replication.factor": "1",
  "errors.deadletterqueue.context.headers.enable": "true"
}
EOF
playground topic wait-for-records --topic dlq --min-expected-messages 2 --max-wait 120
lab_run playground connector diagnose --connector orders-sink --since 1m
lab_expect_exit 0
lab_expect_contains "orders-sink"
lab_expect_contains "RUNNING"
lab_expect_not_contains "WorkerSinkTask{id=orders-sink-0} Task threw an uncaught" "no task failure for the tolerated records"
lab_run playground container exec --container connect --command "wc -l < /tmp/orders.txt"
lab_expect_equals "$(echo "$LAB_OUTPUT" | tail -1 | tr -d ' ')" "3" "lines written by orders-sink (the 3 Avro records)"

log "Step 3: what went to the DLQ, and why"
lab_run playground topic dlq inspect --connector orders-sink
lab_expect_contains "2 records in 1 group(s), most frequent first"
lab_expect_contains "2 record(s) of connector orders-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)"
lab_expect_contains "org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic orders to Avro:"
lab_expect_contains "root cause: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_expect_contains "original records: topic orders partition 0 offsets 3..4 (2)"
lab_expect_contains "dlq partition 0 offsets 0..1"
lab_expect_contains 'sample value: {"id": 1}'
lab_run bash -c "playground topic dlq inspect --topic dlq --grep 'magic byte' --json | jq -c '.groups[] | {count, stage, exception, original_topics}'"
lab_expect_contains '{"count":2,"stage":"VALUE_CONVERTER","exception":"org.apache.kafka.connect.errors.DataException","original_topics":[{"topic":"orders","partition":"0","first_offset":3,"last_offset":4,"count":2}]}'
lab_run playground topic consume -t dlq --last 1 --max-characters 0
lab_expect_contains "__connect.errors.topic:orders"
lab_expect_contains "__connect.errors.stage:VALUE_CONVERTER"
lab_expect_contains 'Value:{"id": 2}'
lab_run bash -c "playground topic consume -t dlq --json --max-messages 1 2>/dev/null | jq -r '.headers[\"__connect.errors.exception.stacktrace\"]'"
lab_expect_contains "org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic orders to Avro:"

log "Step 4: the fix is a JSON sink for these records, so replay them there"
playground connector create-or-update --connector orders-json-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "orders-json",
  "file": "/tmp/orders-json.txt",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
EOF
lab_run playground topic dlq replay --connector orders-sink --to orders-json --dry-run
lab_expect_contains "2 record(s) to topic orders-json"
lab_expect_contains "2 records would be replayed"
lab_run playground topic dlq replay --connector orders-sink --to orders-json
lab_expect_contains "2 records replayed"
lab_run playground connector show-lag --connector orders-json-sink --max-wait 120
lab_expect_contains "is 0 !"
lab_run playground container exec --container connect --command "cat /tmp/orders-json.txt"
lab_expect_contains "{id=1}"
lab_expect_contains "{id=2}"
lab_run playground topic consume -t orders-json
lab_expect_contains 'Headers:NO_HEADERS|Key:null|Value:{"id": 1}' "error headers stripped by the replay"

log "Step 5: replay without a fix, and watch the DLQ grow"
lab_run playground topic dlq replay --connector orders-sink
lab_expect_contains "2 record(s) to topic orders"
playground topic wait-for-records --topic dlq --min-expected-messages 4 --max-wait 60
lab_run playground topic dlq inspect --connector orders-sink
lab_expect_contains "4 records in 1 group(s)"
lab_expect_contains "original records: topic orders partition 0 offsets 3..6 (4)"
lab_expect_contains "dlq partition 0 offsets 0..3"

log "✅ all the outputs of the page are as expected"
