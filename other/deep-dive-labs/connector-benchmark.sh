#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-connector-benchmark
# throughputs depend on the machine: only the lines of the summary and the shape of the result are asserted
lab_require_plaintext
lab_start_environment

playground_cli="${DIR}/../../scripts/cli/playground"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# the html report is never opened in a browser by the lab
export BENCHMARK_NO_OPEN=1

# the benchmark of a sink replays the 'playground topic produce' of the example script that feeds its topic: this one
playground topic produce -t filestream --nb-messages 5 --value '{"id": %g, "name": "name-%g"}'
lab_create_filestream_sink

log "Step 1: a sink, in drain mode"
lab_run playground connector benchmark --connector filestream-sink --nb-records 200000 --interval 1 --no-history --no-flight-recorder --output-dir "$out"
lab_expect_exit 0
lab_expect_contains "🔁 load: replay of the 'playground topic produce' of connector-benchmark.sh to topic filestream"
lab_expect_contains "⏸️ pausing connector filestream-sink (sink, 1 task(s)"
lab_expect_contains "📦 backlog of 200000 records loaded in"
lab_expect_contains "⏯️ resuming connector filestream-sink and waiting for 200000 records"
lab_expect_contains "🏁 benchmark of connector filestream-sink (sink, 1 task(s), org.apache.kafka.connect.file.FileStreamSinkConnector"
lab_expect_contains "throughput"
lab_expect_contains "records/s"
lab_expect_contains "⚠️ results are relative to this docker host: compare runs on the same machine only"
lab_expect_contains "📄 result: $out/"

log "Step 2: again, as JSON"
lab_run bash -c "$playground_cli connector benchmark --connector filestream-sink --nb-records 200000 --interval 1 --no-history --no-flight-recorder --output-dir '$out' --json 2> /dev/null | jq -c '{ok: (.records_per_second > 0 and .records > 0 and .expected_records == 200000 and .type == \"sink\" and .mode == \"drain\" and .tasks == 1)}'"
lab_expect_exit 0
lab_expect_contains '{"ok":true}' "result json: records_per_second > 0, 200000 records expected, sink, drain, 1 task"

log "Step 3: a source, with its benchmark-load.bash"
playground container exec --container connect --command "touch /tmp/lab-benchmark.txt"
playground connector create-or-update --connector filestream-source --wait << 'EOT'
{
     "tasks.max": "1",
     "connector.class": "org.apache.kafka.connect.file.FileStreamSourceConnector",
     "topic": "lab-benchmark",
     "file": "/tmp/lab-benchmark.txt",
     "key.converter": "org.apache.kafka.connect.storage.StringConverter",
     "value.converter": "org.apache.kafka.connect.storage.StringConverter"
}
EOT
# the load script of the FileStream source example (this folder has none)
export BENCHMARK_LOAD_SCRIPT="$(cd "${DIR}/../../connect/connect-filestream-source" && pwd)/benchmark-load.bash"
lab_run playground connector benchmark --connector filestream-source --nb-records 100000 --interval 1 --no-history --no-flight-recorder --output-dir "$out"
lab_expect_exit 0
lab_expect_contains "📥 load: benchmark-load.bash (BENCHMARK_LOAD_SCRIPT)"
lab_expect_contains "📦 backlog of 100000 records loaded"
lab_expect_contains "🏁 benchmark of connector filestream-source (source, 1 task(s), org.apache.kafka.connect.file.FileStreamSourceConnector"
lab_expect_contains "records/s"

lab_run playground connector benchmark --connector filestream-source --shape update --no-history --output-dir "$out"
lab_expect_exit 1
lab_expect_contains "--shape update does not apply to lines appended to a file: use the default --shape bulk"

log "Step 4: steady mode"
lab_run playground connector benchmark --connector filestream-source --mode steady --duration 20s --warmup 5s --nb-records 5000 --interval 2 --no-history --no-flight-recorder --output-dir "$out"
lab_expect_exit 0
lab_expect_contains "🌊 starting the load in the background"
lab_expect_contains "🔥 warm-up for 5s"
lab_expect_contains "⏱️ measuring for 20s"
lab_expect_contains "🛑 stopping the load at the end of its current batch"
lab_expect_contains "steady for"
lab_expect_contains "end-to-end latency"

log "Step 5: why versions can't be compared here"
lab_run playground connector benchmark --connector filestream-source --connector-tag 1.0.0 --connector-tag 1.0.1 --no-history --output-dir "$out"
lab_expect_exit 1
lab_expect_contains "could not find the confluent hub plugin of org.apache.kafka.connect.file.FileStreamSourceConnector in the example"

log "✅ all the outputs of the page are as expected"
