#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-log-levels
lab_require_plaintext
lab_start_environment
lab_create_filestream_sink

log "Step 1: what is set"
lab_run playground debug log-level get
lab_expect_contains "Get log level for all packages"
lab_expect_contains '"org.reflections": {'
lab_run playground debug log-level get --package org.apache.kafka.connect.file
lab_expect_contains '"message":"Logger org.apache.kafka.connect.file not found."' "no level of its own yet"

log "Step 2: TRACE on the FileStream package, and its effect"
lab_run playground debug log-level set --package org.apache.kafka.connect.file --level TRACE
lab_expect_contains "Set log level for package org.apache.kafka.connect.file to TRACE (scope=cluster)"
lab_expect_contains '"level":"TRACE"'
playground topic produce -t filestream --nb-messages 3 --value '{"lab": %g}'
MAX_WAIT=60
CUR_WAIT=0
while true
do
    lab_run playground container logs -c connect --grep "FileStreamSinkTask" --no-follow --tail 200
    if grep -qF "TRACE [filestream-sink|task-0] Writing line to /tmp/output.json: {lab=3}" <<< "$LAB_OUTPUT"
    then
        lab_expect_contains "TRACE [filestream-sink|task-0] Writing line to /tmp/output.json: {lab=1} (org.apache.kafka.connect.file.FileStreamSinkTask"
        break
    fi
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ no TRACE line of FileStreamSinkTask for the 3 new records"
        exit 1
    fi
done

log "Step 3: the same level twice is skipped"
lab_run playground debug log-level set --package org.apache.kafka.connect.file --level TRACE
lab_expect_contains "Skipping as log level for package org.apache.kafka.connect.file was already set to TRACE"

log "Step 4: the connector's loggers in one call"
lab_run playground connector log-level --connector filestream-sink --level DEBUG
lab_expect_contains "also setting io.confluent.kafka.schemaregistry.client.rest.RestService (to see schema registry rest requests) to DEBUG"
lab_expect_contains "also setting org.apache.kafka.connect.runtime.TransformationChain (to see records before and after SMTs) to DEBUG"
lab_expect_contains "also setting org.apache.kafka.connect.runtime.WorkerSinkTask to DEBUG"
lab_expect_contains "Set log level for package org.apache.kafka.connect.file to DEBUG (scope=cluster)"
lab_run playground debug log-level get --package org.apache.kafka.connect.runtime.WorkerSinkTask
lab_expect_contains '"level":"DEBUG"'

log "Step 5: back to normal"
lab_run playground connector log-level --connector filestream-sink --level INFO
lab_expect_contains "Set log level for package org.apache.kafka.connect.file to INFO (scope=cluster)"
lab_run bash -c "playground debug log-level get 2>/dev/null | grep -A1 '\"org.apache.kafka.connect.runtime.WorkerSinkTask\"'"
lab_expect_contains '"level": "INFO"' "WorkerSinkTask is still listed, now at INFO"

# a package name is not checked: a typo is accepted
lab_run playground debug log-level set --package org.apache.kafka.connect.fiel --level DEBUG
lab_expect_exit 0
lab_expect_contains '"level":"DEBUG"'
playground debug log-level set --package org.apache.kafka.connect.fiel --level INFO

log "Step 6: a restart forgets everything"
playground debug log-level set --package org.apache.kafka.connect.file --level TRACE
playground container restart -c connect
playground connector wait --connector filestream-sink --max-wait 180
lab_run playground debug log-level get --package org.apache.kafka.connect.file
lab_expect_contains '"message":"Logger org.apache.kafka.connect.file not found."' "the TRACE is gone after the restart"

log "✅ all the outputs of the page are as expected"
