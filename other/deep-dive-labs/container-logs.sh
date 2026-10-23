#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-container-logs
lab_require_plaintext
lab_start_environment

saved_log=/tmp/lab-connect-$$.log
trap 'rm -f "$saved_log" "$saved_log.gz"' EXIT

log "Step 1: a baseline, then a broken connector"
lab_run playground container logs -c connect --errors
lab_expect_exit 0
lab_expect_contains "ERROR/FATAL digest for connect logs"

# an Avro sink on a topic of plain JSON records
playground connector create-or-update --connector bad-sink --no-wait << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/bad.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
playground connector wait --connector bad-sink --state FAILED --max-wait 120

log "Step 2: the digest"
lab_run playground container logs -c connect --errors --since 5m
lab_expect_contains "ERROR/FATAL digest for connect logs since 5m"
lab_expect_contains "WorkerSinkTask{id=bad-sink-0} Task threw an uncaught and unrecoverable exception"
lab_expect_contains "org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic filestream to Avro:"
lab_expect_contains "Caused by: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_expect_contains "at io.confluent.kafka.serializers.schema.id.SchemaId.fromBytes" "frames of the deepest cause"
playground connector restart --connector bad-sink
playground connector wait --connector bad-sink --state FAILED --max-wait 120
# the same failure after the restart: one finding, x2 (the second failure can take a few seconds to be logged)
MAX_WAIT=60
CUR_WAIT=0
while true
do
    lab_run playground container logs -c connect --errors --since 5m
    if grep -A1 "ERROR x2" <<< "$LAB_OUTPUT" | grep -qF "WorkerSinkTask{id=bad-sink-0}"
    then
        log "✅ the same failure after the restart is one finding: ERROR x2"
        break
    fi
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ the failure of bad-sink is not reported as ERROR x2 after a restart"
        exit 1
    fi
done

log "Step 3: grep, tail, and the follow trap"
lab_run playground container logs -c connect --grep "Unknown magic byte" --no-follow
lab_expect_exit 0
lab_expect_contains "Caused by: java.lang.IllegalArgumentException: Unknown magic byte!"
lab_run playground container logs -c connect --no-follow --tail 5
lab_expect_exit 0
lab_run timeout 5 playground container logs -c connect --since 1m
lab_expect_exit 124

log "Step 4: waiting"
lab_run playground container logs -c connect --wait-for-log "Unknown magic byte" --max-wait 30
lab_expect_exit 0
lab_expect_contains "Waiting up to 30 seconds for message Unknown magic byte to be present in connect container logs..."
lab_expect_contains "The log is there !"
lab_run playground container logs -c connect --wait-for-log "this line never shows up" --max-wait 20
lab_expect_exit 1
lab_expect_contains "The logs in connect container do not show 'this line never shows up' after 20 seconds."

log "Step 5: the same digest, offline"
playground container logs -c connect --no-follow --tail all > "$saved_log" 2>&1
gzip -kf "$saved_log"
lab_run playground analyze logs -f "$saved_log.gz"
lab_expect_exit 0
lab_expect_contains "ERROR/FATAL digest for $saved_log.gz"
lab_expect_contains "WorkerSinkTask{id=bad-sink-0}"
lab_expect_contains "1 file(s) with findings out of 1 scanned (binary files skipped: 0)"
lab_run playground container logs -c connect --errors
lab_expect_exit 0
playground connector delete --connector bad-sink

log "✅ all the outputs of the page are as expected"
