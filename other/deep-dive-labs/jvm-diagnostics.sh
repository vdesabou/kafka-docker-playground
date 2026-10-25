#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-jvm-diagnostics
lab_require_plaintext
lab_start_environment
lab_create_filestream_sink
playground_cli="${DIR}/../../scripts/cli/playground"

out=$(mktemp -d)
producer=""
function cleanup_jvm_lab () {
    if [ -n "$producer" ]
    then
        kill "$producer" > /dev/null 2>&1 || true
    fi
    rm -rf "$out"
}
trap cleanup_jvm_lab EXIT

log "Step 1: the samples, no environment needed"
lab_run playground analyze thread-dump --sample deadlock_jdk21 --output-dir "$out/threads"
lab_expect_exit 0
lab_expect_contains '"deadlock-1"'
lab_expect_contains '"deadlock-2"'
lab_expect_contains "✅ HTML report saved: $out/threads/jdk21-scenario-1-thread-report.html"
lab_run playground analyze gc-logs --sample jdk21_g1_kafka_real --output-dir "$out/gc"
lab_expect_exit 0
lab_expect_contains "✅ HTML report saved: $out/gc/jdk21_g1_kafka_real-gc-report.html"
lab_run playground analyze flight-recorder --sample jdbc_postgres_sink --output-dir "$out/jfr"
lab_expect_exit 0
lab_expect_contains "🛩️  Flight recording of 14 s, 1 task thread(s)"
lab_expect_contains "✅ HTML report saved: $out/jfr/jdbc_postgres_sink-jfr-report.html"
lab_run playground analyze thread-dump -f /etc/hosts --output-dir "$out/threads"
lab_expect_exit 2
lab_expect_contains "❌ No thread dump found in hosts"
lab_run playground analyze tcp-dump --sample kafka_and_network_errors --output-dir "$out/tcp"
lab_expect_exit 0
lab_expect_contains "🟠 HIGH: 1 connection attempt(s) to sample-broker:9999 refused (the SYN was answered with a reset)"
lab_expect_contains "🟠 HIGH: TLS fatal alert certificate_unknown sent by sample-client to sample-tls-server (1x)"
lab_expect_contains "✅ HTML report saved: $out/tcp/kafka_and_network_errors-tcp-dump-report.html"
lab_run playground analyze tcp-dump --sample http_errors --output-dir "$out/tcp"
lab_expect_exit 0
lab_expect_contains "🟠 HIGH: HTTP 500 Internal Server Error from sample-httpserver:9006 for POST /api/payments (2x)"
lab_expect_contains "response: {\"error\": \"Too Many Requests\", \"message\": \"rate limit of 10 requests per second exceeded\"}"
lab_run playground analyze jscissors --sample filestream_sink_bad_json --output-dir "$out/jsc"
lab_expect_exit 0
lab_expect_contains "🟡 MEDIUM: 💥 3 call(s) of JsonConverter.toConnectData threw org.apache.kafka.connect.errors.DataException"
lab_expect_contains "✅ HTML report saved: $out/jsc/filestream_sink_bad_json-jscissors-report.html"

log "Step 2: thread dumps of the running worker"
lab_run playground analyze thread-dump -c connect --count 2 --interval 3 --output-dir "$out/threads"
lab_expect_exit 0
lab_expect_contains "🎯 Taking 2 thread dump(s) of container connect with kill -3, 3 second(s) apart"
lab_expect_contains "✅ 2 thread dump(s) saved in $out/threads/thread-dumps-connect-"
lab_run bash -c "$playground_cli analyze thread-dump -c connect --count 2 --interval 3 --output-dir $out/threads --json 2>/dev/null | jq -c keys"
lab_expect_exit 0
lab_expect_contains '"deadlocks"'
lab_expect_contains '"connect_tasks"'
lab_run playground debug thread-dump -c connect --jstack
lab_expect_exit 1
lab_expect_contains "❌ jstack is not installed in container connect (the image has a JRE only)"
lab_expect_contains "❌ failed to take thread dump on container connect"

log "Step 3: the GC log of the running worker"
lab_run playground analyze gc-logs -c connect --output-dir "$out/gc"
lab_expect_exit 0
lab_expect_contains "📄 Found GC log: /var/log/kafka/connectDistributed-gc.log"
lab_expect_contains "GC log file(s) copied to: $out/gc/gc-logs-connect-"

log "Step 4: a flight recording while data flows"
timeout 60 "$playground_cli" topic produce -t filestream --nb-messages -1 --throughput 200 --value '{"id": %g}' > /dev/null 2>&1 &
producer=$!
sleep 5
lab_run playground analyze flight-recorder -c connect --duration 20s --connector filestream-sink --trace-method org.apache.kafka.connect.file.FileStreamSinkTask::put --output-dir "$out/jfr"
lab_expect_exit 0
lab_expect_contains "🎯 tracing every call of org.apache.kafka.connect.file.FileStreamSinkTask::put (JDK 25 method tracing)"
lab_expect_contains "🛩️ recording connect for 20s with the settings of tools/jfr-analyzer/playground.jfc"
lab_expect_contains "org.apache.kafka.connect.file.FileStreamSinkTask.put(Collection)"
lab_expect_contains "✅ recording saved in $out/jfr/flight-recorder-"
lab_expect_contains "Task thread time, by state"
lab_run playground debug flight-recorder -c connect --action start
lab_expect_contains "🛩️ flight recorder is now started on connect over JMX"
lab_run playground debug flight-recorder -c connect --action start
lab_expect_contains "🛩️ flight recorder is already started on connect"
lab_run playground debug flight-recorder -c connect --action status
lab_expect_contains "🛩️ flight recording running on connect since"
sleep 10
lab_run playground debug flight-recorder -c connect --action stop --output-dir "$out/jfr" --no-analyze
lab_expect_contains "🛩️ flight recording of connect ("
lab_expect_contains "is available at $out/jfr/flight-recorder-connect-"
kill "$producer" > /dev/null 2>&1 || true
producer=""

log "Step 5: trace the calls of the FileStream sink with jscissors"
timeout 90 "$playground_cli" topic produce -t filestream --nb-messages -1 --throughput 20 --value '{"id": %g}' > /dev/null 2>&1 &
producer=$!
lab_run playground debug jscissors -c connect --class org.apache.kafka.connect.file.FileStreamSinkTask --method 'put|flush' --action start
lab_expect_exit 0
lab_expect_contains "💉 loading the agent in the running JVM of connect (no restart)"
lab_expect_contains "✂️ 1 class(es) instrumented in connect: org.apache.kafka.connect.file.FileStreamSinkTask"
sleep 10
lab_run playground debug jscissors -c connect --action status
lab_expect_contains "✂️ jscissors running on connect since"
lab_run playground debug jscissors -c connect --action stop --output-dir "$out/jsc"
lab_expect_exit 0
lab_expect_contains "copied to $out/jsc/jscissors-connect-"
lab_expect_contains "FileStreamSinkTask.put(java.util.Collection)"
kill "$producer" > /dev/null 2>&1 || true
producer=""

# heap dumps are slow (and debug heap-dump restarts connect to install a JDK): not replayed

log "✅ all the outputs of the page are as expected"
