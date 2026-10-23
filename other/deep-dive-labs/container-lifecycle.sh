#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-container-lifecycle
lab_require_plaintext
lab_start_environment
lab_create_filestream_sink

lab_tmp=$(mktemp -d)
trap 'rm -rf "$lab_tmp"' EXIT

log "Step 1: what runs, and who you are inside"
lab_run playground status
lab_expect_contains "🐳 Containers"
lab_expect_contains "connect"
lab_expect_not_contains "💀 some containers are not running" "no container down"
lab_run playground container exec -c connect --command "id"
lab_expect_exit 0
lab_expect_contains "🪄 Executing command in container connect with bash"
lab_expect_contains "uid=1000(appuser) gid=1000(appuser) groups=1000(appuser)"
lab_run playground container exec -c connect --root --command "id"
lab_expect_contains "🪄👑 Executing command as root in container connect with bash"
lab_expect_contains "uid=0(root) gid=0(root) groups=0(root)"
lab_run playground container exec -c connect --command "ls /usr/share/filestream-connectors"
lab_expect_contains "connect_file_file-project.jar"
lab_run playground container exec -c connect --command 'echo $HOSTNAME'
lab_expect_contains "connect"
lab_run playground container exec -c connect --command "test -f /nope"
lab_expect_exit 1
# several -c: a failure on any of them gives exit 1 (here the first one fails, the last one succeeds)
lab_run playground container exec -c connect -c broker --command 'test "$HOSTNAME" = broker'
lab_expect_exit 1

log "Step 2: what Connect really loaded"
lab_run playground container get-properties -c connect
lab_expect_contains "📝 Displaying properties file for connect"
lab_expect_contains "bootstrap.servers=broker:9092"
lab_expect_contains "plugin.path=/usr/share/filestream-connectors"
lab_expect_contains "value.converter=io.confluent.connect.avro.AvroConverter"

log "Step 3: files in and out"
MAX_WAIT=60
CUR_WAIT=0
nb_lines=0
while [ "$nb_lines" != "5" ]
do
    playground container cp --source connect:/tmp/output.json --destination "$lab_tmp/lab-output.json" > /dev/null 2>&1 || true
    nb_lines=$(wc -l < "$lab_tmp/lab-output.json" 2> /dev/null | tr -d ' ' || echo 0)
    if [ "$nb_lines" == "5" ]
    then
        break
    fi
    sleep 5
    CUR_WAIT=$(( CUR_WAIT+5 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ /tmp/output.json of connect doesn't have 5 lines after $MAX_WAIT seconds (got ${nb_lines:-0})"
        exit 1
    fi
done
lab_expect_equals "$nb_lines" "5" "lines of the file copied out of connect"
echo "hello" > "$lab_tmp/lab-marker.txt"
lab_run playground container cp --source "$lab_tmp/lab-marker.txt" --destination connect:/tmp/lab-marker.txt
lab_expect_exit 0
lab_run playground container exec -c connect --command "ls -l /tmp/lab-marker.txt; cat /tmp/lab-marker.txt"
lab_expect_contains "-rw-r--r--"
lab_expect_contains "hello"

log "Step 4: restart keeps, recreate keeps too, a real recreation loses"
playground container restart -c connect
lab_run playground container exec -c connect --command "cat /tmp/lab-marker.txt"
lab_expect_contains "hello" "restart keeps the container"
lab_run playground container recreate
lab_expect_contains "Container connect Running" "nothing changed: connect not rebuilt"
lab_run playground container exec -c connect --command "cat /tmp/lab-marker.txt"
lab_expect_contains "hello" "recreate without a definition change keeps the container"
lab_run playground container set-environment-variables -c connect --env "LAB_VAR: 1"
lab_expect_exit 0
lab_expect_contains "Container connect Recreate"
lab_run playground container exec -c connect --command 'echo "LAB_VAR=$LAB_VAR"; cat /tmp/lab-marker.txt'
lab_expect_contains "LAB_VAR=1"
lab_expect_contains "cat: /tmp/lab-marker.txt: No such file or directory" "a new container"
lab_run playground container recreate
lab_run playground container exec -c connect --command 'echo "LAB_VAR=$LAB_VAR"'
lab_expect_contains "LAB_VAR=" 
lab_expect_not_contains "LAB_VAR=1" "recreate replays the command without your variables"
lab_run playground connector wait --connector filestream-sink --max-wait 180
lab_expect_exit 0
lab_expect_contains "✅ connector filestream-sink is RUNNING (1 task(s))"

log "Step 5: a crash, seen by status"
playground container kill -c connect
lab_run playground status
lab_expect_contains "Exited (137)"
lab_expect_contains "💀 some containers are not running or not healthy"
playground container recreate
lab_run playground connector wait --connector filestream-sink --max-wait 180
lab_expect_exit 0
lab_expect_contains "✅ connector filestream-sink is RUNNING"

# change-jdk is not replayed: it downloads and installs a JDK in the container (slow, needs internet access)

log "✅ all the outputs of the page are as expected"
