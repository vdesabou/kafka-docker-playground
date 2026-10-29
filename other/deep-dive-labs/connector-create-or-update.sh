#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-connector-create-or-update
# run with playground run (an example, not a reproduction model): the wait of create-or-update is strict

lab_require_plaintext
lab_start_environment
lab_create_filestream_sink

log "Step 1: what runs"
lab_run playground connector status -c filestream-sink
lab_expect_exit 0
lab_expect_contains "✅ RUNNING  0:🟢 RUNNING"
lab_run playground connector show-config -c filestream-sink
lab_expect_exit 0
lab_expect_contains "🧰 Current config for connector filestream-sink"
lab_expect_contains "playground connector create-or-update --connector filestream-sink"
lab_expect_contains '"file": "/tmp/output.json"'

log "Step 2: update in place, and see the changes"
lab_run playground connector create-or-update -c filestream-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output2.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "errors.tolerance": "all"
}
EOF
lab_expect_exit 0
lab_expect_contains "🔄 Updating connector filestream-sink"
lab_expect_contains "🔍 changes compared to the running config:"
lab_expect_contains "+ errors.tolerance: all"
lab_expect_contains "~ file: /tmp/output.json → /tmp/output2.json"
lab_expect_contains "⏳ Waiting up to 120 seconds for connector filestream-sink to be RUNNING"
lab_expect_contains "✅ connector filestream-sink is RUNNING (1 task(s)) after"

log "Step 3: validate before deploying"
lab_run playground connector validate << 'EOF'
{
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "tasks.max": "abc"
}
EOF
lab_expect_exit 1
lab_expect_contains "❌ Validation errors found in connector config"
lab_expect_contains "tasks.max ->> Invalid value abc for configuration tasks.max: Not a number of type INT"

log "Step 4: a connector that fails, strict vs --no-wait"
lab_run playground connector create-or-update -c broken-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/does/not/exist/output.json"
}
EOF
lab_expect_exit 1
lab_expect_contains "✅ connector broken-sink was successfully created"
lab_expect_contains "❌ connector broken-sink is FAILED, not waiting for it to be RUNNING"
lab_expect_contains "Couldn't find or create file '/does/not/exist/output.json' for FileStreamSinkTask"
lab_expect_contains "Caused by: java.nio.file.NoSuchFileException: /does/not/exist/output.json"
lab_expect_contains "🩺 diagnosing connector broken-sink"
lab_expect_contains "🔥 a task or the connector FAILED: read the trace above, then after a fix: playground connector restart --connector broken-sink"
lab_expect_contains "❌ connector broken-sink is not RUNNING (use --no-wait to skip the wait)"
playground connector delete -c broken-sink
lab_run playground connector create-or-update -c broken-sink --no-wait << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/does/not/exist/output.json"
}
EOF
lab_expect_exit 0
lab_expect_not_contains "⏳ Waiting up to" "wait with --no-wait"
lab_run playground connector wait -c broken-sink --state FAILED --max-wait 60
lab_expect_exit 0
lab_expect_contains "✅ connector broken-sink is FAILED after"
playground connector delete -c broken-sink

log "Step 5: compare with a customer's config"
customer_config=/tmp/customer-connector.json
cat > "$customer_config" << 'EOF'
{
  "name": "customer-sink",
  "config": {
    "tasks.max": "4",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "filestream",
    "file": "/tmp/output2.json",
    "errors.tolerance": "all"
  }
}
EOF
lab_run playground connector diff -c filestream-sink --file "$customer_config"
lab_expect_exit 0
lab_expect_contains "✏️  tasks.max"
lab_expect_contains "➖ key.converter = org.apache.kafka.connect.storage.StringConverter   (only in filestream-sink)"
lab_expect_contains "📊 4 key(s) differ, 4 identical"
lab_expect_contains "✅ HTML report saved: /tmp/playground-connector-diff/diff-filestream-sink-"
diff_report=$(echo "$LAB_OUTPUT" | sed -n 's/.*HTML report saved: //p' | tail -1)
lab_expect_equals "$(grep -o 'another converter: the records are read' "$diff_report" | head -1)" "another converter: the records are read" "converter finding in the diff HTML report"
lab_run playground connector diff -c filestream-sink --defaults
lab_expect_exit 0
lab_expect_contains "✏️  errors.tolerance = all   (default: none)"
lab_expect_contains "✏️  value.converter = org.apache.kafka.connect.json.JsonConverter   (default: io.confluent.connect.avro.AvroConverter)"
lab_expect_contains "📊 4 parameter(s) differ from their default, 2 are set to their default value (they could be removed)"
lab_expect_contains "💤 tasks.max = 1"
lab_expect_contains "💤 key.converter = org.apache.kafka.connect.storage.StringConverter"

log "Step 6: the REST API format, and --dry-run"
lab_run playground connector create-or-update -c filestream-sink --dry-run "$customer_config"
lab_expect_exit 0
lab_expect_contains "📄 reading the connector config from $customer_config"
lab_expect_contains '📦 detected: REST API format ({"name": ..., "config": {...}})'
lab_expect_contains "- key.converter"
lab_expect_contains "~ tasks.max: 1 → 4"
lab_expect_contains "🌵 --dry-run: connector filestream-sink would be updated with this config"
lab_expect_contains "🌵 request: PUT http://localhost:8083/connectors/filestream-sink/config"
lab_expect_not_contains "it is replaced by the connector name" "warning for the outer name of the REST API format"

log "Step 7: a paused connector stays paused"
playground connector pause -c filestream-sink
lab_run playground connector create-or-update -c filestream-sink "$customer_config"
lab_expect_exit 0
lab_expect_contains "⏸️ connector filestream-sink is PAUSED, it stays PAUSED after the update"
lab_expect_contains "✅ connector filestream-sink is PAUSED (1 task(s)) after"
playground connector resume -c filestream-sink
# the 4 tasks start on resume: a few seconds
MAX_WAIT=60
CUR_WAIT=0
while true
do
    lab_run playground connector status -c filestream-sink
    if grep -qF "3:🟢 RUNNING" <<< "$LAB_OUTPUT"
    then
        break
    fi
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ the 4 tasks of filestream-sink are not RUNNING after $MAX_WAIT seconds"
        exit 1
    fi
done
lab_expect_contains "0:🟢 RUNNING,1:🟢 RUNNING,2:🟢 RUNNING,3:🟢 RUNNING"
rm -f "$customer_config"

log "✅ all the outputs of the page are as expected"
