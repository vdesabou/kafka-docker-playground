#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-network-traffic

# round trip in ms from the "⏱️ round trip from <container> to <destination>: <n> ms" line of the last lab_run
function round_trip_ms () {
    grep "round trip from $1 to $2:" <<< "$LAB_OUTPUT" | tail -1 | sed -E 's/.*: ([0-9.]+) ms.*/\1/'
}

# lab_expect_ms <value> <min> <max> <description>: the measures are not exact, only their order of magnitude is checked
function lab_expect_ms () {
    if [ -z "$1" ] || ! awk -v v="$1" -v min="$2" -v max="$3" 'BEGIN { exit !(v >= min && v <= max) }'
    then
        logerror "❌ $4: expected between $2 and $3 ms, got '$1'"
        exit 1
    fi
    log "✅ $4: $1 ms (between $2 and $3)"
}

lab_require_plaintext
lab_start_environment
lab_create_filestream_sink
playground topic produce -t lab --nb-messages 10 --value '{"f1":"x"}'

log "Step 1: baseline"
lab_run playground debug degrade-traffic -c connect --destination broker --action status
lab_expect_exit 0
lab_expect_contains "✅ no degradation applied on container connect"
lab_expect_contains "(average of 4 pings)"
lab_expect_ms "$(round_trip_ms connect broker)" 0 50 "baseline round trip"

log "Step 2: one-way latency"
lab_run playground debug degrade-traffic -c connect --destination broker --latency 200ms --action start
lab_expect_exit 0
lab_expect_ms "$(round_trip_ms connect broker)" 150 350 "round trip with +200 ms on connect (one-way: +200, not +400)"
lab_run playground debug degrade-traffic -c broker --destination connect --latency 200ms --action start
lab_expect_exit 0
lab_run playground debug degrade-traffic -c connect --destination broker --action status
lab_expect_exit 0
lab_expect_contains "netem"
lab_expect_ms "$(round_trip_ms connect broker)" 350 600 "round trip with +200 ms on both sides"
lab_run playground debug degrade-traffic -c connect -c broker --action stop
lab_expect_exit 0
lab_expect_contains "✅ traffic of container connect is back to normal"
lab_expect_contains "✅ traffic of container broker is back to normal"

log "Step 3: port-scoped degradation"
lab_run playground debug degrade-traffic -c connect --destination broker --port 9092 --latency 300ms --action start
lab_expect_exit 0
lab_expect_contains "tcp connection time from connect to broker:9092:"
lab_expect_contains "(average of 4 connections)"
tcp_ms=$(grep "tcp connection time from connect to broker:9092:" <<< "$LAB_OUTPUT" | tail -1 | sed -E 's/.*9092: ([0-9.]+) ms.*/\1/')
lab_expect_ms "$tcp_ms" 250 600 "tcp connection time with +300 ms on port 9092"
lab_run playground debug degrade-traffic -c connect --destination broker --action status
lab_expect_exit 0
lab_expect_ms "$(round_trip_ms connect broker)" 0 50 "ping round trip (ICMP is in the untouched band)"
lab_run playground debug degrade-traffic -c connect --action stop
lab_expect_exit 0

log "Step 4: outage, then recovery"
lab_run playground debug block-traffic -c connect --destination broker --action start
lab_expect_exit 0
lab_expect_contains "🚫 Blocking traffic on containers connect for all ports for destination broker"
# the error digest depends on the timing of the clients: only checked to return
lab_run playground container logs -c connect --errors --since 2m
lab_expect_exit 0
lab_run playground connector status
lab_expect_exit 0
lab_run playground debug block-traffic -c connect --destination broker --action stop
lab_expect_exit 0
lab_expect_contains "🟢 Unblocking traffic on containers connect for all ports from destination broker"
lab_run playground container logs -c connect --errors --since 1m
lab_expect_exit 0
# does it recover by itself? the FileStream sink does
lab_run playground connector wait --connector filestream-sink --max-wait 120
lab_expect_exit 0

log "✅ all the outputs of the page are as expected"
