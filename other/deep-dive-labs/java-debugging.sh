#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-java-debugging
# testssl (needs a TTY) and generate-diagnostics (downloads a jar from packages.confluent.io) are not replayed
lab_require_plaintext
playground start-environment --environment plaintext --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"

log "Step 1: connect already listens for a debugger"
lab_run playground container logs -c connect --grep "dt_socket" --no-follow
lab_expect_contains "Listening for transport dt_socket at address:" "JDWP agent of connect"
lab_run playground debug enable-remote-debugging
lab_expect_exit 0
lab_expect_contains "enable-remote-debugging is already enabled for connect container connect"
lab_expect_not_contains "enable remote debugging for connect" "connect is not recreated"

log "Step 2: a debugger on the broker"
lab_run playground debug enable-remote-debugging -c broker
lab_expect_exit 0
lab_expect_contains "enable remote debugging for broker"
lab_expect_contains "enabling containers broker with environment variables KAFKA_DEBUG: 'true' JAVA_DEBUG_OPTS: '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=0.0.0.0:5005'"
lab_expect_contains '"port": 5005,'
lab_expect_contains "see https://kafka-docker-playground.io/#/toolkit-debugging?id=✨-remote-debugging"
lab_run playground container logs -c broker --grep "dt_socket" --no-follow
lab_expect_contains "Listening for transport dt_socket at address:" "JDWP agent of the broker"

log "Step 3: back to the original broker"
lab_run playground debug disable-remote-debugging -c broker
lab_expect_exit 0
lab_expect_contains "disable remote debugging for broker"
lab_expect_contains "restore back original values before any changes was made for containers broker"
lab_run playground container logs -c broker --grep "dt_socket" --no-follow
lab_expect_not_contains "Listening for transport dt_socket" "a new broker container, without the variables"

log "Step 4: which jar a class comes from"
lab_run playground debug java-debug -c connect --type class_loading
lab_expect_exit 0
lab_expect_contains "enabling containers connect with environment variables KAFKA_OPTS: -verbose:class"
lab_create_filestream_sink
MAX_WAIT=60
CUR_WAIT=0
while true
do
    lab_run playground container logs -c connect --grep "FileStreamSinkTask source:" --no-follow
    if grep -qF "FileStreamSinkTask source:" <<< "$LAB_OUTPUT"
    then
        lab_expect_contains "[class,load] org.apache.kafka.connect.file.FileStreamSinkTask source:"
        lab_expect_contains "/usr/share/filestream-connectors/" "the jar of the plugin path"
        break
    fi
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ no class loading line for FileStreamSinkTask"
        exit 1
    fi
done
lab_run playground container logs -c connect --grep "dt_socket" --no-follow
lab_expect_contains "Listening for transport dt_socket at address:" "KAFKA_OPTS changed, the debugger is still there"

log "Step 5: the traces off"
lab_run playground debug java-debug -c connect --type class_loading --action disable
lab_expect_exit 0
lab_expect_contains "restore back original values before any changes was made for containers connect"
lab_run playground container logs -c connect --grep "class,load" --no-follow
lab_expect_not_contains "[class,load]" "no class loading trace in the new connect container"
playground connector wait --connector filestream-sink --max-wait 180

log "✅ all the outputs of the page are as expected"
