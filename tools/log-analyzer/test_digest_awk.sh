#!/bin/bash
# The digest (summarize_log_errors of scripts/cli/src/lib/cli_function.sh) with every awk given: mawk (the default awk of
# Debian / Ubuntu), gawk, busybox awk, the awk of macOS. It must run with each of them and find the same records: a
# construct one of them refuses ("cut is duplicated in argument list" of mawk) made the whole digest fail on that system.
#
#   tools/log-analyzer/test_digest_awk.sh mawk gawk "busybox awk"
set -u
shopt -s nullglob
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed -n '/^function summarize_log_errors/,/^}/p' "$root/scripts/cli/src/lib/cli_function.sh" > "$tmp/digest.sh"
samples=("$root/tools/log-analyzer/samples/connect-oracle-xstream-task-failure.log" "$root"/tools/log-analyzer/samples/kafka-clients/*.log
         "$root"/tools/log-analyzer/samples/kafka-streams/*.log "$root"/tools/log-analyzer/samples/compare/*.log)
# the events of the INFO lines (lifecycle, GC pauses of 1 s or more, process stops, controller changes): same with every awk
cat > "$tmp/events.log" << 'EOF'
[2026-11-07 10:00:00,000] INFO [KafkaServer id=2] started (kafka.server.KafkaServer)
[2026-11-07 10:10:00,000] INFO [KafkaServer id=2] shutting down (kafka.server.KafkaServer)
[2026-11-07 10:10:01,000] INFO [BrokerServer id=1] Transition from STARTED to SHUTTING_DOWN (kafka.server.BrokerServer)
[2026-11-07 10:20:00,000] INFO [QuorumController id=3] Becoming the active controller at epoch 7, next write offset 1. (org.apache.kafka.controller.QuorumController)
[2026-11-07 10:21:00,000] INFO Kafka Connect stopping (org.apache.kafka.connect.runtime.Connect)
%7|1762509600.000|INIT|rdkafka#producer-1| [thrd:app]: librdkafka v2.3.0 (0x20300ff) rdkafka#producer-1 initialized (builtin.features gzip,snappy)
[2026-11-07T10:25:00.000+0000][gc] GC(2) Pause Full (G1 Compaction Pause) 990M->950M(1G) 2512.789ms
[2026-11-07T10:25:01.000+0000][gc] GC(3) Pause Young (Normal) (G1 Evacuation Pause) 100M->50M(1G) 12.3ms
2026-11-07T10:26:00.000+0000: 12.3: [Full GC (Allocation Failure) [PSYoungGen: 1K->0K(2K)] 900K->800K(1000K), 1.8234560 secs] [Times: user=1 sys=0, real=1.82 secs]
[2026-11-07 10:28:00,000] INFO [jdbc-sink|task-0] Initializing writer using SQL dialect: SqlServerDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask:72)
[2026-11-07 10:28:00,001] INFO [jdbc-sink|task-0] Initializing writer using SQL dialect: SqlServerDatabaseDialect (io.confluent.connect.jdbc.sink.JdbcSinkTask:72)
[2026-11-07 10:28:00,002] INFO [jdbc-sink|task-0] Committing offsets (org.apache.kafka.connect.runtime.WorkerSinkTask:330)
2026-11-07T10:27:00.000+0000: 13.0: [GC (Allocation Failure) [ParNew: 26240K->1637K(29504K), 0.0053837 secs] 26240K->1637K(95040K), 0.0128474 secs] [Times: user=0.01 sys=0.00, real=0.01 secs]
EOF
# a line of a log written on Windows (CRLF)
printf '%s\r\n' '[2026-11-07 10:28:00,003] INFO [hdfs-sink|task-1] Starting commit and rotation (io.confluent.connect.hdfs3.TopicPartitionWriter:298)' >> "$tmp/events.log"
samples+=("$tmp/events.log")
failed=0
reference=""
for awk_cmd in "$@"
do
    name=$(printf '%s' "$awk_cmd" | tr -c 'A-Za-z0-9' '-')
    bin="$tmp/bin-$name"
    mkdir -p "$bin"
    printf '#!/bin/sh\nexec %s "$@"\n' "$awk_cmd" > "$bin/awk"
    chmod +x "$bin/awk"
    out="$tmp/out-$name"
    : > "$out"
    for f in "${samples[@]}"
    do
        if ! PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2.records" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out" "$f" > "$out.digest" 2> "$out.err"
        then
            echo "❌ $awk_cmd: the digest of $(basename "$f") failed: $(head -n 2 "$out.err" | tr '\n' ' ')"
            failed=1
        fi
        grep -E '^🔎 ' "$out.digest" | sed "s|^|$(basename "$f"): |" >> "$out"
    done
    grep -E '^@@PGEVTN?@@' "$out.records" >> "$out"
    expected=$'gc_pause 2\nprocess_stop 3\ncontroller_change 1'
    got=$(grep -E '^@@PGEVT@@'$'\t''(gc_pause|process_stop|controller_change)' "$out.records" | cut -f2 | sort | uniq -c | awk '{print $2, $1}' | sort -r -k1,1)
    if [ "$got" != "$(printf '%s\n' "$expected" | sort -r -k1,1)" ]
    then
        echo "❌ $awk_cmd: events of events.log: $(printf '%s' "$got" | tr '\n' ',') instead of $(printf '%s' "$expected" | tr '\n' ',')"
        failed=1
    fi
    # the loggers of the lines of the tasks (the plugin of a connector whose startup is not in the logs): each once, not the
    # ones of the runtime, a CRLF line too
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 == "plugin_logger" && ($5 == "jdbc-sink" || $5 == "hdfs-sink") {print $5, $6}' "$out.records" | sort | tr '\n' ',')
    if [ "$got" != "hdfs-sink io.confluent.connect.hdfs3.TopicPartitionWriter,jdbc-sink io.confluent.connect.jdbc.sink.JdbcSinkTask," ]
    then
        echo "❌ $awk_cmd: plugin_logger events of events.log: $got"
        failed=1
    fi
    if [ -z "$reference" ]
    then
        reference="$out"
        echo "✅ $awk_cmd: $(grep -vc "^@@" "$out") file(s) with records, $(grep -c "^@@PGEVT@@" "$out") event(s)"
    elif diff -q "$reference" "$out" > /dev/null
    then
        echo "✅ $awk_cmd: same records as $1"
    else
        echo "❌ $awk_cmd: other records than $1:"
        diff "$reference" "$out" | head -n 10
        failed=1
    fi
done
exit $failed
