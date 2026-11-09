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
[2026-11-07 10:28:00,001] INFO [jdbc-source|task-0] Using JDBC dialect PostgreSql (io.confluent.connect.jdbc.source.JdbcSourceTask:135)
[2026-11-07 10:28:00,002] INFO [jdbc-sink|task-0] Committing offsets (org.apache.kafka.connect.runtime.WorkerSinkTask:330)
[2026-11-07 10:28:00,002] INFO [jdbc-sink|task-0] Committing offsets asynchronously (org.apache.kafka.connect.runtime.WorkerCoordinator:330)
[2026-11-07 10:28:00,002] ERROR [mdm-sink|task-1] Error encountered in task mdm-sink-1. Executing stage 'TRANSFORMATION' with class 'org.apache.kafka.connect.runtime.TransformationStage', where consumed record is {topic='t', partition=1, offset=4, timestamp=1, timestampType=CreateTime}. (org.apache.kafka.connect.runtime.errors.LogReporter:70)
2026-11-07T10:27:00.000+0000: 13.0: [GC (Allocation Failure) [ParNew: 26240K->1637K(29504K), 0.0053837 secs] 26240K->1637K(95040K), 0.0128474 secs] [Times: user=0.01 sys=0.00, real=0.01 secs]
	jvm.spec = Eclipse Adoptium, OpenJDK 64-Bit Server VM, 25.0.4.1, 25.0.4.1+1-LTS
[2026-11-07 10:29:00,000] INFO Client environment:java.version=17.0.9 (org.apache.zookeeper.ZooKeeper)
[0.004s][info][gc,init] Version: 21.0.5+11-LTS (release)
WARNING: A terminally deprecated method in sun.misc.Unsafe has been called
WARNING: sun.misc.Unsafe::arrayBaseOffset has been called by com.google.protobuf.UnsafeUtil
EOF
# a line of a log written on Windows (CRLF)
printf '%s\r\n' '[2026-11-07 10:28:00,003] INFO [hdfs-sink|task-1] Starting commit and rotation (io.confluent.connect.hdfs3.TopicPartitionWriter:298)' >> "$tmp/events.log"
samples+=("$tmp/events.log")
# config changes between restarts only: two instances of a class in one run are not a change (the readiness check of the
# image then the worker), a restart with another value is, and so is a connector reconfigured without a restart
{
    printf '%s\n' '[2026-11-07 11:00:00,000] INFO AdminClientConfig values: ' $'\tbootstrap.servers = [broker:9092]' $'\tclient.id = ' \
        '[2026-11-07 11:00:10,000] INFO DistributedConfig values: ' $'\toffset.flush.interval.ms = 10000' \
        '[2026-11-07 11:00:11,000] INFO AdminClientConfig values: ' $'\tbootstrap.servers = [PLAINTEXT://broker:9092]' $'\tclient.id = ' \
        '[2026-11-07 11:00:12,000] INFO Kafka Connect started (org.apache.kafka.connect.runtime.Connect:77)' \
        '[2026-11-07 11:01:00,000] INFO [s3-sink|worker] SinkConnectorConfig values: ' $'\tname = s3-sink' $'\ttasks.max = 1' \
        '[2026-11-07 11:02:00,000] INFO [s3-sink|worker] SinkConnectorConfig values: ' $'\tname = s3-sink' $'\ttasks.max = 4' \
        '[2026-11-07 11:10:00,000] INFO Kafka Connect stopping (org.apache.kafka.connect.runtime.Connect:83)' \
        '[2026-11-07 11:11:00,000] INFO DistributedConfig values: ' $'\toffset.flush.interval.ms = 60000' \
        '[2026-11-07 11:11:05,000] ERROR boom (x.Y)'
} > "$tmp/config-changes.log"
samples+=("$tmp/config-changes.log")
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
    expected=$'gc_pause 2\nprocess_stop 4\ncontroller_change 1'
    got=$(grep -E '^@@PGEVT@@'$'\t''(gc_pause|process_stop|controller_change)' "$out.records" | cut -f2 | sort | uniq -c | awk '{print $2, $1}' | sort -r -k1,1)
    if [ "$got" != "$(printf '%s\n' "$expected" | sort -r -k1,1)" ]
    then
        echo "❌ $awk_cmd: events of events.log: $(printf '%s' "$got" | tr '\n' ',') instead of $(printf '%s' "$expected" | tr '\n' ',')"
        failed=1
    fi
    # the loggers of the lines of the tasks (the plugin of a connector whose startup is not in the logs): each once, not the
    # ones of the runtime but its sink / source task classes, a CRLF line too
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 == "plugin_logger" && ($5 == "jdbc-sink" || $5 == "hdfs-sink") {print $5, $6}' "$out.records" | sort | tr '\n' ',')
    if [ "$got" != "hdfs-sink io.confluent.connect.hdfs3.TopicPartitionWriter,jdbc-sink io.confluent.connect.jdbc.sink.JdbcSinkTask,jdbc-sink org.apache.kafka.connect.runtime.WorkerSinkTask," ]
    then
        echo "❌ $awk_cmd: plugin_logger events of events.log: $got"
        failed=1
    fi
    # the SQL dialect of a JDBC connector (sink and source wording), each once; the record of an error of the runtime
    # (LogReporter): a sink
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 == "connector_hint" {print $5, $6}' "$out.records" | sort | tr '\n' ',')
    if [ "$got" != "jdbc-sink dialect SqlServerDatabaseDialect,jdbc-source dialect PostgreSql,mdm-sink direction sink," ]
    then
        echo "❌ $awk_cmd: connector_hint events of events.log: $got"
        failed=1
    fi
    # the JVM of the components (jvm.spec of a Connect worker, java.version=, the Version: of a GC log), and the warnings of
    # the JDK launcher on stderr ("WARNING: sun.misc.Unsafe::…") are not records
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 == "jvm_version" {print $6}' "$out.records" | sort | tr '\n' ',')
    if [ "$got" != "17.0.9,21.0.5+11-LTS,25.0.4.1+1-LTS Eclipse Adoptium," ]
    then
        echo "❌ $awk_cmd: jvm_version events of events.log: $got"
        failed=1
    fi
    got=$(awk -F '\t' '$1 == "@@PGCFGCHG@@" {print $4 "->" $5}' "$out.records" | sort | tr '\n' ',')
    if [ "$got" != "offset.flush.interval.ms=10000->offset.flush.interval.ms=60000,tasks.max=1->tasks.max=4," ]
    then
        echo "❌ $awk_cmd: config changes of config-changes.log: $got"
        failed=1
    fi
    if grep -q 'sun\.misc\.Unsafe' "$out.records"
    then
        echo "❌ $awk_cmd: a WARNING: line of the JDK launcher is a record"
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
