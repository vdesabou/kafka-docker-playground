#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/streams-functions.bash

# tumbling windows of 1 minute with a grace period of 30 seconds, final result only (suppress): out-of-order and late
# records. The event time is the "ts" field of the value, so the records below land in known windows
start_streams_scenario windowed

# 2026-01-01T00:00:00Z: window 1 is [00:00:00, 00:01:00), closed when the stream time reaches 00:01:30
T0=1767225600000

# produces a reading of sensor-a at T0 + $1 seconds
function produce_reading () {
    log "📤 sensor-a reading at T0+$1s"
    playground topic produce --topic windowed-input --nb-messages 1 --key "sensor-a" --value "{\"ts\":$(( T0 + $1 * 1000 )),\"value\":1}" --value-format raw > /dev/null
}

log "📥 3 readings in window 1"
produce_reading 0
produce_reading 10
produce_reading 20
log "⏭️ A reading in window 2 (T0+70s): the stream time moves to 00:01:10, window 1 is still open (grace period until 00:01:30)"
produce_reading 70
log "🔀 An out-of-order reading for window 1 (T0+50s), within the grace period: still counted"
produce_reading 50
log "⏭️ A reading at T0+100s: the stream time passes 00:01:30, window 1 closes and suppress emits its final count, 4"
produce_reading 100

wait_for_records windowed-output 'length == 1 and .[0].key == "sensor-a@2026-01-01T00:00:00Z" and .[0].value == 4' "one final result for window 1: 4 readings (the out-of-order one included), nothing emitted before the window closed"

log "🐌 A late reading for window 1 (T0+30s), after its grace period: dropped (dropped-records-total), window 1 stays at 4"
late_at=$(now)
produce_reading 30
wait_for_log_since "$late_at" "dropped-records-total" streams streams2 streams3

log "⏭️ A reading at T0+200s: window 2 [00:01:00, 00:02:00) closes with 2 readings (T0+70s and T0+100s)"
produce_reading 200
wait_for_records windowed-output 'length == 2 and (map({(.key): .value}) | add) == {"sensor-a@2026-01-01T00:00:00Z": 4, "sensor-a@2026-01-01T00:01:00Z": 2}' "window 1 emitted once (4, the late reading not counted), window 2: 2"
