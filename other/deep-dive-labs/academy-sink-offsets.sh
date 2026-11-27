#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of the sink offsets exercises of https://kafka-docker-playground.io/#/academy (a new sink that skips the records
# already in the topic, a read_committed sink blocked by an open transaction): runs their reproduction models
# (academy/connect-connect-filestream-sink) and asserts the symptom each exercise is about, then the fix the page gives
lab_require_plaintext
academy="${DIR}/../../academy"

function run_model () {
    lab_run bash -c "cd '$academy/$1' && bash '$2'"
}

log "Exercise: the new connector skips the records already in the topic"
run_model connect-connect-filestream-sink filestream-sink-repro-000024-new-sink-skips-existing-records.sh
# the file only (the output of the model also prints the records it produces)
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"order": 3, "day": "today"}'
lab_expect_not_contains '"day": "yesterday"}' "yesterday's orders are skipped"
lab_run playground connector lint --connector filestream-sink
lab_expect_contains "MEDIUM consumer.override.auto.offset.reset = latest"
lab_run playground connector offsets reset --connector filestream-sink
lab_expect_contains "⚠️ filestream-sink has consumer.override.auto.offset.reset=latest"

log "Exercise, Step 3: without auto.offset.reset=latest, then a reset"
playground connector create-or-update --connector filestream-sink << 'EOF'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "orders",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF
lab_run playground connector offsets reset --connector filestream-sink
lab_expect_not_contains "⚠️ filestream-sink has consumer.override.auto.offset.reset=latest" "no warning once the key is removed"
sleep 15
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"order": 1, "day": "yesterday"}'

log "Exercise: read_committed, and nothing is written"
run_model connect-connect-filestream-sink filestream-sink-repro-000025-read-committed-sink-stuck-open-transaction.sh
lab_expect_contains "no offset committed yet"
lab_run playground connector diagnose --connector filestream-sink
lab_expect_contains "🔒 the sink reads read_committed: an open transaction blocks it at its first offset"
lab_run playground broker transactions describe-producers --topic payments
lab_expect_contains "0 ⚠️"

log "Exercise, Step 3: abort the transaction"
lab_run playground broker transactions abort --topic payments --partition 0 --start-offset 0
lab_run playground connector show-lag --connector filestream-sink --max-wait 60
lab_expect_contains "are transaction markers (COMMIT / ABORT), not records"
lab_run playground container exec -c connect --command "cat /tmp/output.json"
lab_expect_contains '{"payment": 5, "batch": "new"}'
lab_expect_not_contains '"batch": "crashed"}' "the aborted payments are not written"

log "✅ academy sink offsets lab: the exercises behave as the page says"
