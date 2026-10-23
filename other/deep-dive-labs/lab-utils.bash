#!/bin/bash
# Helpers shared by the deep dive labs (sourced, not run: run-tests.sh only runs the *.sh files of the folder).
# Each lab replays the hands-on lab of a page of https://kafka-docker-playground.io/#/deep-dives and fails as soon
# as an output quoted in the page changes, so that a CLI change that makes a page wrong shows up in CI.

# the labs are written for the plaintext environment (container names, ports, docker exec)
function lab_require_plaintext () {
    if [ "${PLAYGROUND_ENVIRONMENT:-plaintext}" != "plaintext" ]
    then
        logwarn "the deep dive labs are written for the plaintext environment, skipping with ${PLAYGROUND_ENVIRONMENT}"
        exit 111
    fi
}

# starts the plaintext environment with the FileStream connectors, and 5 records in topic filestream
function lab_start_environment () {
    playground start-environment --environment plaintext --docker-compose-override-file "${DIR}/docker-compose.plaintext.yml"
    playground topic produce -t filestream --nb-messages 5 --value '{"id": %g, "name": "name-%g"}'
}

# creates the filestream-sink connector of the page labs: topic filestream to /tmp/output.json
function lab_create_filestream_sink () {
    playground connector create-or-update --connector filestream-sink --wait << 'EOT'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
     "topics": "filestream",
     "file": "/tmp/output.json",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable": "false"
}
EOT
}

# runs a command, keeps its output (stdout and stderr, colors removed) in $LAB_OUTPUT and its exit code in $LAB_EXIT,
# and prints the output: lab_run playground topic consume -t orders --count
# (stdin is passed to the command, for heredocs; use lab_run bash -c "… | jq …" for a pipe)
function lab_run () {
    log "🧪 $*"
    local raw_output
    raw_output=$(mktemp)
    set +e
    "$@" > "$raw_output" 2>&1
    LAB_EXIT=$?
    set -e
    LAB_OUTPUT=$(perl -pe 's/\e\[[0-9;?]*[A-Za-z]//g' "$raw_output")
    rm -f "$raw_output"
    echo "$LAB_OUTPUT"
}

# repeated spaces are squeezed in the output and in the text, so that column alignment doesn't change the result
# the connector type label depends on the folder of the example (🌎onprem for connect/, ⛈️👷self managed or nothing
# for other/): it is removed too, the pages were recorded with connect/ examples
function lab_squeeze () {
    perl -pe 's/(🌎onprem|⛈️👷self managed) //g; s/ +/ /g' <<< "$1"
}

# lab_expect_contains "<text>" [description]: fails the lab when the output of the last lab_run doesn't contain <text>
function lab_expect_contains () {
    if ! grep -qF -- "$(lab_squeeze "$1")" <<< "$(lab_squeeze "$LAB_OUTPUT")"
    then
        logerror "❌ ${2:-expected output} not found: $1"
        exit 1
    fi
    log "✅ ${2:-found}: $1"
}

# lab_expect_not_contains "<text>" [description]
function lab_expect_not_contains () {
    if grep -qF -- "$(lab_squeeze "$1")" <<< "$(lab_squeeze "$LAB_OUTPUT")"
    then
        logerror "❌ ${2:-unexpected output} found: $1"
        exit 1
    fi
    log "✅ ${2:-not found, as expected}: $1"
}

# lab_expect_exit <code>: fails the lab when the exit code of the last lab_run is not <code>
function lab_expect_exit () {
    if [ "$LAB_EXIT" != "$1" ]
    then
        logerror "❌ expected exit code $1, got $LAB_EXIT"
        exit 1
    fi
    log "✅ exit code $1"
}

# lab_expect_equals "<actual>" "<expected>" [description]
function lab_expect_equals () {
    if [ "$1" != "$2" ]
    then
        logerror "❌ ${3:-value}: expected '$2', got '$1'"
        exit 1
    fi
    log "✅ ${3:-value}: $2"
}
