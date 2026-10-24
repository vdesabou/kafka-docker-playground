#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-offsets-and-lag
lab_require_plaintext
lab_start_environment
lab_create_filestream_sink

# `connector offsets alter` opens the offsets in the editor of `playground config get editor` and waits for it: use a
# scripted editor that applies the jq filter of $lab_tmp/filter, and restore the editor at the end
lab_tmp=$(mktemp -d)
prev_editor=$(playground config get editor 2>/dev/null | tail -1)
cat > "$lab_tmp/editor.sh" << EOF
#!/bin/bash
jq "\$(cat $lab_tmp/filter)" "\$1" > "\$1.new" && mv "\$1.new" "\$1"
EOF
chmod +x "$lab_tmp/editor.sh"
playground config set editor "$lab_tmp/editor.sh"
trap 'playground config set editor "${prev_editor:-code}"; rm -rf "$lab_tmp"' EXIT

# wait_for_line_count <container file> <expected>: the number of lines a FileStream sink wrote, with a bounded wait
function wait_for_line_count () {
    local file="$1"
    local expected="$2"
    local count=""
    MAX_WAIT=120
    CUR_WAIT=0
    while true
    do
        count=$(playground container exec --container connect --command "wc -l < $file" 2>/dev/null | tail -1 | tr -d ' ')
        if [ "$count" == "$expected" ]
        then
            log "✅ $file has $expected lines"
            return
        fi
        sleep 5
        CUR_WAIT=$(( CUR_WAIT+5 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ $file has $count lines, expected $expected"
            exit 1
        fi
    done
}

# wait_for_record_count <topic> <expected>: the number of records of a topic, with a bounded wait
function wait_for_record_count () {
    local topic="$1"
    local expected="$2"
    local count=""
    MAX_WAIT=60
    CUR_WAIT=0
    while true
    do
        count=$(playground topic consume -t "$topic" --count 2>/dev/null | tail -1)
        if [ "$count" == "$expected" ]
        then
            log "✅ topic $topic has $expected records"
            return
        fi
        sleep 5
        CUR_WAIT=$(( CUR_WAIT+5 ))
        if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
        then
            logerror "❌ topic $topic has $count records, expected $expected"
            exit 1
        fi
    done
}

log "Step 1: lag and offsets of a sink"
lab_run playground connector show-lag --connector filestream-sink --interval 5 --max-wait 90
lab_expect_contains "consumer lag for connector filestream-sink is 0 !"
lab_run playground connector offsets get --connector filestream-sink
lab_expect_contains '"kafka_topic": "filestream"'
lab_expect_contains '"kafka_offset": 5'
lab_run playground consumer-group describe --group connect-filestream-sink
lab_expect_contains "Total lag for consumer group connect-filestream-sink: 0"

log "Step 2: a paused sink has no lag to show"
playground connector pause --connector filestream-sink
playground topic produce -t filestream --nb-messages 20 --value '{"id": %g}'
lab_run playground consumer-group describe --group connect-filestream-sink
lab_expect_contains "Total lag for consumer group connect-filestream-sink: 20"
lab_run playground connector show-lag --connector filestream-sink --interval 5 --max-wait 30
lab_expect_exit 1
lab_expect_contains "connector filestream-sink instance is not in ✅ RUNNING state after 60s"
playground connector resume --connector filestream-sink
lab_run playground connector show-lag --connector filestream-sink --interval 5 --max-wait 90
lab_expect_exit 0
lab_expect_contains "consumer lag for connector filestream-sink is 0 !"

log "Step 3: the group of a running sink can't be reset from outside"
lab_run playground consumer-group reset-offsets --group connect-filestream-sink --to-earliest
lab_expect_exit 1
lab_expect_contains "Assignments can only be reset if the group 'connect-filestream-sink' is inactive"
lab_expect_contains "connect-filestream-sink is the group of sink connector filestream-sink: use playground connector offsets reset|alter --connector filestream-sink"

log "Step 4: reset = everything again"
lab_run playground connector offsets reset --connector filestream-sink
lab_expect_contains "The offsets for this connector have been reset successfully"
# 25 records, then the same 25 again
wait_for_line_count /tmp/output.json 50

log "Step 5: rewind by N records, the stopped-group way"
# wait for the commit at 25 (lag: - until then)
lab_run playground connector show-lag --connector filestream-sink --interval 5 --max-wait 90
lab_expect_contains "consumer lag for connector filestream-sink is 0 !"
playground connector stop --connector filestream-sink
lab_run playground consumer-group reset-offsets --group connect-filestream-sink --topic filestream --shift-by -3 --dry-run
lab_expect_exit 0
lab_expect_contains "NEW-OFFSET"
lab_expect_contains "Nothing was changed, run again without --dry-run to apply"
if ! grep -qE "connect-filestream-sink +filestream +0 +22" <<< "$LAB_OUTPUT"
then
    logerror "❌ the dry run doesn't show the new offset 22"
    exit 1
fi
lab_run playground consumer-group reset-offsets --group connect-filestream-sink --topic filestream --shift-by -3
lab_expect_exit 0
lab_expect_contains "Offsets of consumer group connect-filestream-sink reset"
playground connector resume --connector filestream-sink
# the last 3 records again
wait_for_line_count /tmp/output.json 53

log "Step 6: offsets of a source"
playground container exec --container connect --command "bash -c 'seq -f line-%g 1 10 > /tmp/lab-source.txt'"
playground connector create-or-update --connector filestream-source << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
  "topic": "lab-source",
  "file": "/tmp/lab-source.txt",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOF
lab_run playground topic consume -t lab-source --min-expected-messages 10 --timeout 60
lab_expect_contains "Value:line-10"
# the source offsets are flushed every offset.flush.interval.ms (60 s): empty until then
MAX_WAIT=120
CUR_WAIT=0
while true
do
    lab_run playground connector offsets get --connector filestream-source
    if grep -qF '"position": 71' <<< "$LAB_OUTPUT"
    then
        lab_expect_contains '"filename": "/tmp/lab-source.txt"'
        break
    fi
    sleep 10
    CUR_WAIT=$(( CUR_WAIT+10 ))
    if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]
    then
        logerror "❌ the offset of filestream-source is not position 71 (10 lines, 71 bytes) after $MAX_WAIT seconds"
        exit 1
    fi
done
lab_run playground connector show-lag --connector filestream-source
lab_expect_contains "Skipping source connector filestream-source, it must be a sink to show the lag"

# back to the start of line-10 (byte 63): line-10 is sent again
echo '.offsets[0].offset.position = 63' > "$lab_tmp/filter"
# the editor is never opened on CI (GITHUB_RUN_NUMBER set): clear it for this command, so that the scripted editor runs
GITHUB_RUN_NUMBER="" lab_run playground connector offsets alter --connector filestream-source
lab_expect_contains "The offsets for this connector have been altered successfully"
lab_expect_contains '"position": 63'
wait_for_record_count lab-source 11

# reset: the whole file again
lab_run playground connector offsets reset --connector filestream-source
lab_expect_contains "The offsets for this connector have been reset successfully"
wait_for_record_count lab-source 21

log "✅ all the outputs of the page are as expected"
