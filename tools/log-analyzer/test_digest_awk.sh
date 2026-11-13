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
# log_awk picks mawk when it is installed: PLAYGROUND_AWK=awk makes it run the awk wrapper of each test below
export PLAYGROUND_AWK=awk
sed -n '/^function log_awk/,/^}/p' "$root/scripts/cli/src/lib/cli_function.sh" > "$tmp/log_awk.sh"
{ cat "$tmp/log_awk.sh"; sed -n '/^function summarize_log_errors/,/^}/p' "$root/scripts/cli/src/lib/cli_function.sh"; } > "$tmp/digest.sh"
# the --since / --until window of analyze logs (log_window_filter of scripts/cli/src/commands/analyze/logs.sh)
{ cat "$tmp/log_awk.sh"; sed -n '/^function window_epoch/,/^}/p;/^function log_window_filter/,/^}/p' "$root/scripts/cli/src/commands/analyze/logs.sh"; } > "$tmp/window.sh"
printf '%s\n' 'header' '[2026-11-01 10:00:00,000] ERROR old' '  at a.b(C.java:1)' '[2026-11-08 10:00:00,000] ERROR new' '  at a.b(C.java:2)' > "$tmp/window-iso.log"
printf '%s\n' '%3|1793896102.923|FAIL|rdkafka#producer-1| new' '%3|1700000000.000|FAIL|rdkafka#producer-1| old' > "$tmp/window-epoch.log"
printf '%s\n' 'no time on this line' 'ERROR nor on this one' > "$tmp/window-none.log"
samples=("$root/tools/log-analyzer/samples/connect-oracle-xstream-task-failure.log" "$root"/tools/log-analyzer/samples/kafka-clients/*.log
         "$root"/tools/log-analyzer/samples/kafka-streams/*.log "$root"/tools/log-analyzer/samples/compare/*.log
         "$root"/tools/log-analyzer/samples/connect-workers/worker-?/connect.log "$root/tools/log-analyzer/samples/grafana-loki-export.txt"
         "$root/tools/log-analyzer/samples/connector-cr/connect-0.txt")
# the events of the INFO lines (lifecycle, GC pauses of 1 s or more, process stops and failed starts, controller changes): same with every awk
cat > "$tmp/events.log" << 'EOF'
[2026-11-07 10:00:00,000] INFO [KafkaServer id=2] started (kafka.server.KafkaServer)
[2026-11-07 10:10:00,000] INFO [KafkaServer id=2] shutting down (kafka.server.KafkaServer)
[2026-11-07 10:10:01,000] INFO [BrokerServer id=1] Transition from STARTED to SHUTTING_DOWN (kafka.server.BrokerServer)
[2026-11-07 10:20:00,000] INFO [QuorumController id=3] Becoming the active controller at epoch 7, next write offset 1. (org.apache.kafka.controller.QuorumController)
[2026-11-07 10:20:59,000] ERROR Failed to start Connect (org.apache.kafka.connect.cli.AbstractConnectCli:178)
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
[2026-11-07 10:30:00,000] INFO [GroupCoordinator 1]: Member consumer-orders-1-0b1c in group orders has failed, removing it from the group (kafka.coordinator.group.GroupCoordinator)
[2026-11-07 10:30:05,000] INFO [GroupCoordinator 1]: Group orders removed dynamic members who haven't joined: Set(consumer-orders-2-9f1e) (kafka.coordinator.group.GroupCoordinator)
[2026-11-07 10:30:30,000] INFO [GroupCoordinator 1]: Preparing to rebalance group payments in state CompletingRebalance with old generation 5 (__consumer_offsets-3) (reason: Removing [consumer-p-2] on pending sync request expiration) (kafka.coordinator.group.GroupCoordinator)
[2026-11-07 10:31:00,000] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=7] [GroupId connect-s3-sink] Member connector-consumer-s3-sink-0-77aa has failed, removing it from the group. (org.apache.kafka.coordinator.group.GroupMetadataManager)
[2026-11-07 10:31:05,000] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=7] [GroupId connect-s3-sink] Removed dynamic members who haven't joined: [connector-consumer-s3-sink-1-88bb] (org.apache.kafka.coordinator.group.GroupMetadataManager)
[2026-11-07 10:32:00,000] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=7] [GroupId payments] Preparing to rebalance the group in state CompletingRebalance with old generation 4 (reason: Removing [consumer-p-1] on pending sync request expiration). (org.apache.kafka.coordinator.group.GroupMetadataManager)
[2026-11-07 10:40:00,000] INFO [Partition orders-0 broker=1] Shrinking ISR from 1,2,3 to 1,3. Leader: (highWatermark: 100, endOffset: 120). Out of sync replicas: (brokerId: 2, endOffset: 100, lastCaughtUpTimeMs: 1762508370000). (kafka.cluster.Partition)
[2026-11-07 10:40:01,000] INFO [Partition orders-1 broker=1] Shrinking ISR from 1,2 to 1. Leader: (highWatermark: 5, endOffset: 9). (kafka.cluster.Partition)
[2026-11-07 10:40:30,000] INFO [Partition orders-0 broker=1] Expanding ISR from 1,3 to 1,3,2 (kafka.cluster.Partition)
[2026-11-07 10:40:02,000] INFO [ReplicaFetcher replicaId=2, leaderId=1, fetcherId=0] Error sending fetch request (sessionId=123, epoch=45) to node 1: (org.apache.kafka.clients.FetchSessionHandler)
[2026-11-07 10:40:03,000] WARN [ReplicaFetcher replicaId=2, leaderId=1, fetcherId=0] Error in response for fetch request (type=FetchRequest, replicaId=2, maxWait=500) (kafka.server.ReplicaFetcherThread)
[2026-11-07 10:40:04,000] INFO [Consumer clientId=connector-consumer-s3-sink-0, groupId=connect-s3-sink] Error sending fetch request (sessionId=INVALID, epoch=INITIAL) to node 2: (org.apache.kafka.clients.FetchSessionHandler)
[2026-11-07 10:40:04,000] INFO [Producer clientId=producer-1] Disconnecting from node 1 due to request timeout. (org.apache.kafka.clients.NetworkClient)
[2026-11-07 10:40:05,000] ERROR [kafka-log-cleaner-thread-0]: Error due to (kafka.log.LogCleaner)
[2026-11-07 10:40:06,000] INFO Attempting to send response via channel for which there is no open connection, connection id 172.18.0.5:9092-172.18.0.9:51234-3 (kafka.network.Processor)
%5|1762512007.000|THROTTLE|rdkafka#producer-1| [thrd:broker:9092/2]: broker:9092/2: ProduceRequest throttled by broker for 512ms
[2026-11-07 10:41:00,000] INFO [DynamicConfigPublisher broker id=1] Updating node 1 with new configuration : leader.replication.throttled.rate -> 10485760 (kafka.server.metadata.DynamicConfigPublisher)
[2026-11-07 10:41:00,100] INFO [DynamicConfigPublisher broker id=2] Updating node 2 with new configuration :  (kafka.server.metadata.DynamicConfigPublisher)
[2026-11-07 10:41:01,000] INFO [DynamicConfigPublisher broker id=1] Updating cluster configuration : confluent.balancer.throttle.bytes.per.second -> 52428800 (kafka.server.metadata.DynamicConfigPublisher)
[2026-11-07 10:41:02,000] INFO [DynamicConfigPublisher broker id=1] Updating topic orders with new configuration : leader.replication.throttled.replicas -> 0:1,0:4,follower.replication.throttled.replicas -> 0:1,retention.ms -> 1000 (kafka.server.metadata.DynamicConfigPublisher)
[2026-11-07 10:41:03,000] INFO [DynamicConfigPublisher broker id=1] Updating topic payments with new configuration : retention.ms -> 1000 (kafka.server.metadata.DynamicConfigPublisher)
EOF
# a line of a log written on Windows (CRLF)
printf '%s\r\n' '[2026-11-07 10:28:00,003] INFO [hdfs-sink|task-1] Starting commit and rotation (io.confluent.connect.hdfs3.TopicPartitionWriter:298)' >> "$tmp/events.log"
samples+=("$tmp/events.log")
# config changes between restarts only: two instances of a class in one run are not a change (the readiness check of the
# image then the worker), a restart with another value is, and so is a connector reconfigured without a restart. Two clients
# with the same client.id in each run (latest and earliest) are compared with the closest one of the earlier runs; a new
# instance next to the old one in the same run (the converter of a connector next to the one of the worker) is not a change
{
    printf '%s\n' '[2026-11-07 11:00:00,000] INFO AdminClientConfig values: ' $'\tbootstrap.servers = [broker:9092]' $'\tclient.id = ' \
        '[2026-11-07 11:00:10,000] INFO DistributedConfig values: ' $'\toffset.flush.interval.ms = 10000' \
        '[2026-11-07 11:00:11,000] INFO AdminClientConfig values: ' $'\tbootstrap.servers = [PLAINTEXT://broker:9092]' $'\tclient.id = ' \
        '[2026-11-07 11:00:12,000] INFO Kafka Connect started (org.apache.kafka.connect.runtime.Connect:77)' \
        '[2026-11-07 11:01:00,000] INFO [s3-sink|worker] SinkConnectorConfig values: ' $'\tname = s3-sink' $'\ttasks.max = 1' \
        '[2026-11-07 11:02:00,000] INFO [s3-sink|worker] SinkConnectorConfig values: ' $'\tname = s3-sink' $'\ttasks.max = 4' \
        '[2026-11-07 11:03:00,000] INFO ConsumerConfig values: ' $'\tauto.offset.reset = latest' $'\tclient.id = lic' $'\tmax.poll.records = 500' \
        '[2026-11-07 11:03:01,000] INFO ConsumerConfig values: ' $'\tauto.offset.reset = earliest' $'\tclient.id = lic' $'\tmax.poll.records = 500' \
        '[2026-11-07 11:03:02,000] INFO JsonConverterConfig values: ' $'\tconverter.type = key' $'\tschemas.cache.size = 128' \
        '[2026-11-07 11:10:00,000] INFO Kafka Connect stopping (org.apache.kafka.connect.runtime.Connect:83)' \
        '[2026-11-07 11:11:00,000] INFO DistributedConfig values: ' $'\toffset.flush.interval.ms = 60000' \
        '[2026-11-07 11:11:01,000] INFO ConsumerConfig values: ' $'\tauto.offset.reset = earliest' $'\tclient.id = lic' $'\tmax.poll.records = 500' \
        '[2026-11-07 11:11:02,000] INFO ConsumerConfig values: ' $'\tauto.offset.reset = latest' $'\tclient.id = lic' $'\tmax.poll.records = 100' \
        '[2026-11-07 11:11:03,000] INFO JsonConverterConfig values: ' $'\tconverter.type = key' $'\tschemas.cache.size = 128' \
        '[2026-11-07 11:11:04,000] INFO JsonConverterConfig values: ' $'\tconverter.type = key' $'\tschemas.cache.size = 1000' \
        '[2026-11-07 11:11:05,000] ERROR boom (x.Y)'
} > "$tmp/config-changes.log"
samples+=("$tmp/config-changes.log")
# two appenders: each line written twice in a row (to the millisecond), a stack trace twice as a block, collapsed by
# pairs. The same text at another millisecond, and a stack frame repeated inside a trace, are not duplicates
{
    printf '%s\n' '[2026-11-07 12:00:00,001] ERROR [orders-sink|task-0] boom (x.Y:1)' '[2026-11-07 12:00:00,001] ERROR [orders-sink|task-0] boom (x.Y:1)' \
        '[2026-11-07 12:00:00,002] ERROR [orders-sink|task-0] boom (x.Y:1)' \
        '[2026-11-07 12:00:01,000] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:225)' \
        '[2026-11-07 12:00:01,000] INFO [Worker clientId=connect-1, groupId=connect-cluster] Rebalance started (org.apache.kafka.connect.runtime.distributed.WorkerCoordinator:225)' \
        '[2026-11-07 12:00:02,003] ERROR [orders-sink|task-0] task failed (x.Y:2)' 'java.lang.IllegalStateException: bad' $'\tat a.b(C.java:1)' $'\tat a.b(C.java:1)' \
        '[2026-11-07 12:00:02,003] ERROR [orders-sink|task-0] task failed (x.Y:2)' 'java.lang.IllegalStateException: bad' $'\tat a.b(C.java:1)' $'\tat a.b(C.java:1)' \
        '[2026-11-07 12:00:03,000] INFO done (x.Y:3)'
    # a WARN logged twice in the same millisecond (once per column), through the two appenders: 4 lines, 2 events
    for i in 1 2 3 4; do printf '%s\n' '[2026-11-07 12:00:04,005] WARN [orders-source|task-0] JDBC type -156 (sql_variant) not currently supported (x.Dialect:1)'; done
} > "$tmp/dup.log"
# a Grafana / Loki export (Download as txt): header, epoch and UTC time before each line, newest first, the frames of a
# trace without prefix, an event id (UUID) in each message
{
    printf '%s\n' '"3 lines shown — 0.01% (5min) of 1h"' 'Total bytes processed: "1.2  MB"' \
        'Common labels: {"app":"connect","level":"ERROR","service_name":"connect"}' '' ''
    printf '1793959203000\t2026-11-07T10:00:03.000Z\t[2026-11-07 11:00:03,000] ERROR Failed to produce event log message: {"id":"6f1c0d2e-1a2b-4c3d-8e9f-0a1b2c3d4e5f","type":"x"} (a.B)\n'
    printf '1793959202000\t2026-11-07T10:00:02.000Z\t[2026-11-07 11:00:02,000] ERROR Failed to produce event log message: {"id":"0b2d4f6a-8c0e-4a1b-9c2d-3e4f5a6b7c8d","type":"x"} (a.B)\n'
    printf '1793959201000\t2026-11-07T10:00:01.000Z\t[2026-11-07 11:00:01,000] ERROR [orders-sink|task-0] task failed (x.Y:2)\njava.lang.IllegalStateException: bad\n\tat a.b(C.java:1)\n'
} > "$tmp/loki.log"
# the broker side of an authentication incident (INFO lines of kafka.network.Selector, three formats), the client side
# (not an event of the broker), and an HDFS sink that rotates with empty offsets and never commits next to one that commits
{
    printf '%s\n' '[2026-11-07 13:00:00,000] INFO [SocketServer listenerType=BROKER, nodeId=1] Failed authentication with /10.0.0.1 (channelId=10.0.0.9:9092-10.0.0.1:50001-1) (errorMessage={"status":"Authentication failed"}) (org.apache.kafka.common.network.Selector)' \
        '[2026-11-07 13:00:01,000] INFO [SocketServer listenerType=BROKER, nodeId=1] Failed authentication with /10.0.0.1 (channelId=10.0.0.9:9092-10.0.0.1:50002-2) (errorMessage={"status":"Authentication failed"}) (org.apache.kafka.common.network.Selector)' \
        '[2026-11-07 13:00:02,000] INFO [SocketServer listenerType=BROKER, nodeId=1] Failed re-authentication with /10.0.0.2 (channelId=10.0.0.9:9092-10.0.0.2:50003-3) (errorMessage=Authentication failed: Invalid username or password) (org.apache.kafka.common.network.Selector)' \
        '[2026-11-07 13:00:03,000] INFO [SocketServer listenerType=ZK_BROKER, nodeId=2] Failed authentication with /10.0.0.3 (channelId=10.0.0.8:9092-10.0.0.3:50004-4) (userId=alice, errorMessage=Authentication failed: Invalid username or password) (org.apache.kafka.common.network.Selector)' \
        '[2026-11-07 13:00:04,000] INFO [AdminClient clientId=adminclient-1] Failed authentication with broker.example.com/10.0.0.9 (channelId=-1) (Authentication failed) (org.apache.kafka.common.network.Selector)' \
        '[2026-11-07 13:01:00,000] INFO [hdfs-sink|task-0] Starting commit and rotation for topic partition orders-0 with start offsets {} and end offsets {} (io.confluent.connect.hdfs3.TopicPartitionWriter:615)' \
        '[2026-11-07 13:01:05,000] INFO [hdfs-sink|task-0] Starting commit and rotation for topic partition orders-0 with start offsets {} and end offsets {} (io.confluent.connect.hdfs3.TopicPartitionWriter:615)' \
        '[2026-11-07 13:01:06,000] INFO [ok-sink|task-0] Starting commit and rotation for topic partition pay-0 with start offsets {pay-0=1} and end offsets {pay-0=9} (io.confluent.connect.hdfs3.TopicPartitionWriter:615)' \
        '[2026-11-07 13:01:07,000] INFO [ok-sink|task-0] Committed hdfs://nn/topics/pay/partition=0/pay+0+0000000001+0000000009.avro for pay-0 (io.confluent.connect.hdfs3.TopicPartitionWriter:880)'
} > "$tmp/signals.log"
# a config dump whose tab indentation became spaces (copied from a ticket or a web console), then a driver stack whose
# deepest cause starts with JDK socket and reflection frames: the keys are read, and the frames shown are the driver's
{
    printf '%s\n' '[2026-11-07 14:00:00,000] INFO [db-source|worker] JdbcSourceConnectorConfig values:' \
        '        connection.url = jdbc:as400://db.example.com:9471/LIB1;secure=true' \
        '        mode = incrementing' \
        '        table.whitelist = [SCHEMA1/VIEW1]' \
        ' (org.apache.kafka.common.config.AbstractConfig:383)' \
        '[2026-11-07 14:02:20,000] ERROR [db-source|worker] Failed to start connector (org.apache.kafka.connect.runtime.distributed.DistributedHerder:2246)' \
        'org.apache.kafka.connect.errors.ConnectException: java.sql.SQLNonTransientConnectionException: cannot establish the connection. (Connect timed out)' \
        '        at io.confluent.connect.jdbc.util.CachedConnectionProvider.getConnection(CachedConnectionProvider.java:62)' \
        'Caused by: java.net.SocketTimeoutException: Connect timed out' \
        '        at java.base/sun.nio.ch.NioSocketImpl.timedFinishConnect(NioSocketImpl.java:551)' \
        '        at java.base/java.net.Socket.connect(Socket.java:633)' \
        '        at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)' \
        '        at java.base/java.lang.reflect.Method.invoke(Method.java:569)' \
        '        at com.example.driver.PortLookup.open(PortLookup.java:289)' \
        '        at com.example.driver.PortLookup.socket(PortLookup.java:177)' \
        '        at com.example.driver.Session.connect(Session.java:3781)' \
        '        at com.example.driver.Session.login(Session.java:1509)' \
        '        ... 24 more'
    # only JDK frames: they are kept
    printf '%s\n' '[2026-11-07 14:03:00,000] ERROR [db-source|worker] other failure (x.Y:1)' \
        'java.net.SocketTimeoutException: Read timed out' \
        '        at java.base/sun.nio.ch.NioSocketImpl.timedRead(NioSocketImpl.java:288)'
} > "$tmp/spaces.log"
failed=0
reference=""
for awk_cmd in "$@"
do
    name=$(printf '%s' "$awk_cmd" | tr -c 'A-Za-z0-9' '-')
    bin="$tmp/bin-$name"
    mkdir -p "$bin"
    # the awk given by its path: the wrapper is named awk and comes first on PATH, "exec awk" would run itself forever
    awk_bin=$(command -v "${awk_cmd%% *}") || { echo "❌ $awk_cmd: not found"; failed=1; continue; }
    printf '#!/bin/sh\nexec %s%s "$@"\n' "$awk_bin" "${awk_cmd#"${awk_cmd%% *}"}" > "$bin/awk"
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
    # one stop per file until a start: the KafkaServer and BrokerServer lines of events.log are one stop (then the 2
    # Kafka Connect stopping of events.log and config-changes.log)
    expected=$'gc_pause 2\nprocess_stop 3\ncontroller_change 1'
    got=$(grep -E '^@@PGEVT@@'$'\t''(gc_pause|process_stop|controller_change)' "$out.records" | cut -f2 | sort | uniq -c | awk '{print $2, $1}' | sort -r -k1,1)
    if [ "$got" != "$(printf '%s\n' "$expected" | sort -r -k1,1)" ]
    then
        echo "❌ $awk_cmd: events of events.log: $(printf '%s' "$got" | tr '\n' ',') instead of $(printf '%s' "$expected" | tr '\n' ',')"
        failed=1
    fi
    # one start of a worker logs both "worker initialization took" and "Kafka Connect started": one process start; a start
    # after a stop that only logs "Kafka Connect started": one more (2, not 3)
    printf '%s\n' '[2026-11-07 11:00:00,000] INFO Kafka Connect worker initialization took 2000ms (org.apache.kafka.connect.cli.AbstractConnectCli:88)' \
        '[2026-11-07 11:00:01,000] INFO Kafka Connect started (org.apache.kafka.connect.runtime.Connect:57)' \
        '[2026-11-07 11:00:02,000] ERROR [orders-sink|task-0] boom (org.example.Sink:1)' \
        '[2026-11-07 11:10:00,000] INFO Kafka Connect stopping (org.apache.kafka.connect.runtime.Connect:67)' \
        '[2026-11-07 11:20:00,000] INFO Kafka Connect started (org.apache.kafka.connect.runtime.Connect:57)' > "$tmp/starts.log"
    : > "$out.starts"
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.starts" "$tmp/starts.log" > /dev/null 2>&1
    got=$(grep -c "^@@PGEVT@@"$'\t'"process_start"$'\t' "$out.starts")
    if [ "$got" != 2 ]
    then
        echo "❌ $awk_cmd: $got process start(s) in starts.log instead of 2"
        failed=1
    fi
    # one graceful stop of a KRaft broker (the signal, its state, its own "shutting down", the managers and fetchers it stops,
    # the lifecycle manager) is one stop, not a restart loop; a broker killed twice while it waits for its authorizer: two
    # stops, three start attempts (process_starting), one start; the authorizer, its endpoints, the auth reader of the
    # metadata service and the log recovery after the unclean stop
    printf '%s\n' '[2026-11-07 12:00:00,000] INFO [BrokerServer id=1] Transition from STARTING to STARTED (kafka.server.BrokerServer)' \
        '[2026-11-07 12:00:00,100] INFO [KafkaRaftServer nodeId=1] Kafka Server started (kafka.server.KafkaRaftServer)' \
        '[2026-11-07 12:10:00,000] INFO Terminating process due to signal SIGTERM (org.apache.kafka.common.utils.LoggingSignalHandler)' \
        '[2026-11-07 12:10:00,100] INFO [BrokerServer id=1] Transition from STARTED to SHUTTING_DOWN (kafka.server.BrokerServer)' \
        '[2026-11-07 12:10:00,200] INFO [BrokerServer id=1] shutting down (kafka.server.BrokerServer)' \
        '[2026-11-07 12:10:00,300] INFO [ReplicaFetcherManager on broker 1] shutting down (kafka.server.ReplicaFetcherManager)' \
        '[2026-11-07 12:10:00,400] INFO [data-plane Kafka Request Handler on Broker 1] shutting down (kafka.server.KafkaRequestHandlerPool)' \
        '[2026-11-07 12:10:00,500] INFO [BrokerLifecycleManager id=1] Transitioning from PENDING_CONTROLLED_SHUTDOWN to SHUTTING_DOWN. (kafka.server.BrokerLifecycleManager)' \
        '[2026-11-07 12:10:01,000] INFO [ReplicaFetcherThread-0-2-Default]: Shutting down (kafka.server.ReplicaFetcherThread)' \
        '[2026-11-07 12:10:05,000] INFO [ControllerServer id=1] shutting down (kafka.server.ControllerServer)' \
        '[2026-11-07 12:11:00,000] INFO [BrokerServer id=1] Transition from SHUTDOWN to STARTING (kafka.server.BrokerServer)' \
        '[2026-11-07 12:11:01,000] INFO Starting Kafka Auth reader (io.confluent.security.store.kafka.clients.KafkaReader)' \
        "[2026-11-07 12:11:02,000] INFO Immediately resolve Authorizer future for endpoint: Endpoint(listenerName='REPLICATION', securityProtocol=SASL_SSL, host='broker-1.example.com', port=9091) (kafka.authorizer.logger)" \
        "[2026-11-07 12:11:02,100] INFO Wait for authorizerServerStartFuture authorizerEnableEndpointsFuture futures to complete before enabling endpoint: Endpoint(listenerName='CLIENT', securityProtocol=SASL_SSL, host='broker-1.example.com', port=9092) (kafka.authorizer.logger)" \
        '[2026-11-07 12:11:03,000] INFO [BrokerServer id=1] Waiting for all of the authorizer futures to be completed (kafka.server.BrokerServer)' \
        '[2026-11-07 12:25:00,000] INFO Terminating process due to signal SIGTERM (org.apache.kafka.common.utils.LoggingSignalHandler)' \
        '[2026-11-07 12:25:10,000] INFO [BrokerServer id=1] Transition from SHUTDOWN to STARTING (kafka.server.BrokerServer)' \
        '[2026-11-07 12:25:20,000] INFO Recovering 4321 logs from /var/lib/kafka/data since no clean shutdown file was found (kafka.log.LogManager)' \
        '[2026-11-07 12:26:00,000] INFO Kafka Auth reader initialized on all partitions (io.confluent.security.store.kafka.clients.KafkaReader)' \
        '[2026-11-07 12:26:01,000] INFO [BrokerServer id=1] Finished waiting for all of the authorizer futures to be completed (kafka.server.BrokerServer)' \
        '[2026-11-07 12:26:02,000] INFO [BrokerServer id=1] Transition from STARTING to STARTED (kafka.server.BrokerServer)' \
        '[2026-11-07 12:26:02,100] INFO [KafkaRaftServer nodeId=1] Kafka Server started (kafka.server.KafkaRaftServer)' \
        '[2026-11-07 12:26:03,000] ERROR boom (x.Y)' > "$tmp/broker-stops.log"
    : > "$out.bstops"
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.bstops" "$tmp/broker-stops.log" > /dev/null 2>&1
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" {print $3 " " $2 (($6 != "") ? "=" $6 : "")}' "$out.bstops" | tr '\n' ',')
    expected='1 process_start=Kafka broker started,3 process_stop=Kafka broker stopping on SIGTERM,11 process_starting=Kafka broker starting,12 auth_reader_start,13 authorizer_endpoint_open=REPLICATION:9091,14 authorizer_endpoint_wait=CLIENT:9092,15 authorizer_wait,16 process_stop=Kafka broker stopping on SIGTERM,17 process_starting=Kafka broker starting,18 unclean_recovery=4321,19 auth_reader_ready,20 authorizer_ready,21 process_start=Kafka broker started,'
    if [ "$got" != "$expected" ]
    then
        echo "❌ $awk_cmd: broker stops and starts of broker-stops.log: $got instead of $expected"
        failed=1
    fi
    # the signals of a broker under pressure (ISR changes, followers that cannot fetch, requests timing out, log cleaner,
    # responses to clients already gone, quota throttling): keyed by the broker, with the partition or the peer. The fetch
    # error of a consumer (same FetchSessionHandler line) is not a follower that cannot fetch
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 ~ /^(isr_shrink|isr_expand|replica_fetch_error|request_timeout|log_cleaner|quota_throttle|response_dropped)$/ {print $2 "=" $6}' "$out.records" | LC_ALL=C sort | tr '\n' ',')
    if [ "$got" != "isr_expand=broker 1 · orders-0 (1,3 -> 1,3,2),isr_shrink=broker 1 · orders-0 (1,2,3 -> 1,3),isr_shrink=broker 1 · orders-1 (1,2 -> 1),log_cleaner=log cleaner · thread died,quota_throttle=broker 2 · ProduceRequest,replica_fetch_error=broker 1 · follower 2,replica_fetch_error=broker 1 · follower 2,request_timeout=broker 1 · Producer,response_dropped=broker · client gone before the response," ]
    then
        echo "❌ $awk_cmd: broker signal events of events.log: $got"
        failed=1
    fi
    # the broker configs changed live (not the empty update of a start) and the topics given throttled replicas (a move)
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 ~ /^(dynamic_config|replica_move)$/ {print $2 "=" $6}' "$out.records" | LC_ALL=C sort | tr '\n' ',')
    if [ "$got" != "dynamic_config=broker 1 · cluster: confluent.balancer.throttle.bytes.per.second -> 52428800,dynamic_config=broker 1 · node: leader.replication.throttled.rate -> 10485760,replica_move=broker 1 · orders: 0:1,0:4," ]
    then
        echo "❌ $awk_cmd: live config events of events.log: $got"
        failed=1
    fi
    # 1000 ISR shrinks: the first 300 noted, then the last 150 (the incident at the end of a long log keeps its bursts)
    awk 'BEGIN { for (i = 0; i < 1000; i++) printf "[2026-11-07 %02d:%02d:%02d,000] INFO [Partition orders-%d broker=1] Shrinking ISR from 1,2,3 to 1,3 (kafka.cluster.Partition)\n", 8 + int(i * 7 / 3600), int(i * 7 / 60) % 60, (i * 7) % 60, i % 7 }' > "$tmp/isr-1000.log"
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.isr" "$tmp/isr-1000.log" > /dev/null 2>&1
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 == "isr_shrink" {n++; if (n == 300 || n == 301) printf "%s,", $3; last = $3} END {print n "," last}' "$out.isr")
    if [ "$got" != "300,851,450,1000" ]
    then
        echo "❌ $awk_cmd: 1000 ISR shrinks: line of the 300th, 301st event, events, last line: $got instead of 300,851,450,1000"
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
    # the members removed by the group coordinator of a broker (session timeout, rebalance timeout, pending sync), from the
    # Scala coordinator and from the Java one with and without its [GroupId …] prefix: the group, the timeout, the connector
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 == "member_eviction" {print $5 "=" $6}' "$out.records" | LC_ALL=C sort | tr '\n' ',')
    if [ "$got" != "=orders · rebalance timeout (did not rejoin),=orders · session timeout (no heartbeat),=payments · rebalance timeout (joined, did not sync),=payments · rebalance timeout (joined, did not sync),s3-sink=connect-s3-sink · rebalance timeout (did not rejoin),s3-sink=connect-s3-sink · session timeout (no heartbeat)," ]
    then
        echo "❌ $awk_cmd: member_eviction events of events.log: $got"
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
    # two appenders: the duplicated lines collapsed (2 single lines, a trace of 4 lines, 2 of the 4 copies of a WARN), the
    # same text at another millisecond kept, said in the digest and in @@PGFILE@@
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.dup" "$tmp/dup.log" > "$out.dup.digest" 2>&1
    got=$(awk -F '\t' '$1 == "@@PGFILE@@" {printf "dup=%s,", $8} $1 == "@@PGREC@@" {printf "x%s,", $3} $1 == "@@PGEVTN@@" {printf "%s=%s,", $2, $4}' "$out.dup"; grep -c '^⚠️ 8 duplicated line(s) collapsed' "$out.dup.digest")
    if [ "$got" != "dup=8,x2,x1,x2,worker_rebalance=1,1" ]
    then
        echo "❌ $awk_cmd: duplicated lines of dup.log: $got instead of dup=8,x2,x1,x2,worker_rebalance=1,1"
        failed=1
    fi
    # a Grafana / Loki export: the prefix removed, the header not a record, the event ids masked (one record), newest first
    # detected (first seen = the oldest occurrence, at the bottom; the oldest record first)
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.loki" "$tmp/loki.log" > "$out.loki.digest" 2>&1
    got=$(awk -F '\t' '$1 == "@@PGFILE@@" {printf "%s,", $9} $1 == "@@PGREC@@" {printf "x%s %s-%s %s %s,", $3, $4, $5, $6, $7} $1 == "@@PGTS@@" {printf "[%s],", $2}' "$out.loki"; grep -c 'Common labels' "$out.loki")
    if [ "$got" != "newest_first,x1 8-8 2026-11-07T11:00:01 2026-11-07T11:00:01,[2026-11-07T11:00:01],x2 7-6 2026-11-07T11:00:02 2026-11-07T11:00:03,[2026-11-07T11:00:02 2026-11-07T11:00:03],0" ]
    then
        echo "❌ $awk_cmd: Grafana / Loki export loki.log: $got"
        failed=1
    fi
    # the broker side of an authentication incident: an event of the broker, counted per broker and per client IP and error
    # (not the client side); the sink rotating with empty offsets, and the commits of another one counted
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.sig" "$tmp/signals.log" > /dev/null 2>&1
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 != "plugin_logger" {print "E " $2 "=" $6} $1 == "@@PGEVTN@@" {print "N " $2 "=" $3 "=" $4}' "$out.sig" | LC_ALL=C sort | tr '\n' ',')
    expected='E auth_failure=broker 1 · /10.0.0.1 failed authentication: {"status":"Authentication failed"},E auth_failure=broker 1 · /10.0.0.1 failed authentication: {"status":"Authentication failed"},E auth_failure=broker 1 · /10.0.0.2 failed re-authentication: Authentication failed: Invalid username or password,E auth_failure=broker 2 · /10.0.0.3 failed authentication: Authentication failed: Invalid username or password,E sink_empty_rotation=hdfs-sink · orders-0,E sink_empty_rotation=hdfs-sink · orders-0,N auth_failure=broker 1=3,N auth_failure=broker 2=1,N auth_failure_by=broker 1 · /10.0.0.1 failed authentication: {"status":"Authentication failed"}=2,N auth_failure_by=broker 1 · /10.0.0.2 failed re-authentication: Authentication failed: Invalid username or password=1,N auth_failure_by=broker 2 · /10.0.0.3 failed authentication: Authentication failed: Invalid username or password=1,N sink_commit=ok-sink=1,N sink_empty_rotation=hdfs-sink=2,'
    if [ "$got" != "$expected" ]
    then
        echo "❌ $awk_cmd: authentication failures and empty rotations of signals.log: $got"
        failed=1
    fi
    # the JDK launcher on stderr ("WARNING: sun.misc.Unsafe::…") are not records
    got=$(awk -F '\t' '$1 == "@@PGEVT@@" && $2 == "jvm_version" {print $6}' "$out.records" | sort | tr '\n' ',')
    if [ "$got" != "17.0.9,21.0.5+11-LTS,25.0.4.1+1-LTS Eclipse Adoptium," ]
    then
        echo "❌ $awk_cmd: jvm_version events of events.log: $got"
        failed=1
    fi
    got=$(awk -F '\t' '$1 == "@@PGCFGCHG@@" {print $4 "->" $5}' "$out.records" | sort | tr '\n' ',')
    if [ "$got" != "max.poll.records=500->max.poll.records=100,offset.flush.interval.ms=10000->offset.flush.interval.ms=60000,tasks.max=1->tasks.max=4," ]
    then
        echo "❌ $awk_cmd: config changes of config-changes.log: $got"
        failed=1
    fi
    # the config dump indented with spaces, and the frames of the driver rather than the JDK ones
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.spaces" "$tmp/spaces.log" > /dev/null 2>&1
    got=$(awk -F '\t' '$1 == "@@PGCFG@@" {print "C " $2 " " $3} $1 == "@@PGCFGL@@" {print "L " $2}' "$out.spaces" | tr '\n' ',')
    if [ "$got" != "C JdbcSourceConnectorConfig [db-source|worker],L connection.url=jdbc:as400://db.example.com:9471/LIB1;secure=true,L mode=incrementing,L table.whitelist=[SCHEMA1/VIEW1]," ]
    then
        echo "❌ $awk_cmd: config dump indented with spaces of spaces.log: $got"
        failed=1
    fi
    got=$(grep -E '^ +at ' "$out.spaces" | sed 's/^ *//' | tr '\n' ',')
    if [ "$got" != "at com.example.driver.PortLookup.open(PortLookup.java:289),at com.example.driver.PortLookup.socket(PortLookup.java:177),at com.example.driver.Session.connect(Session.java:3781),at java.base/sun.nio.ch.NioSocketImpl.timedRead(NioSocketImpl.java:288)," ]
    then
        echo "❌ $awk_cmd: frames of the deepest cause of spaces.log (the driver's, not the JDK's; the JDK's when alone): $got"
        failed=1
    fi
    if grep -q 'sun\.misc\.Unsafe' "$out.records"
    then
        echo "❌ $awk_cmd: a WARNING: line of the JDK launcher is a record"
        failed=1
    fi
    # 📈 the INFO lines as templates: the [connector|task-0] context apart (task-0 and task-1 one template), the first word of
    # a leading [Consumer …] kept, numbers, hex ids, UUIDs, ip:port, quoted values, bracketed lists and {…} masked (an empty
    # {} kept: an HDFS rotation with empty offsets is not one with offsets), the failed authentications of a broker (their
    # own fast path) one template whatever the client IP; counted per minute
    awk 'BEGIN {
        for (i = 0; i < 60; i++) printf "[2026-11-07 15:%02d:%02d,000] INFO [orders-sink|task-%d] Starting commit and rotation for topic partition orders-%d with start offsets {} and end offsets {} (io.confluent.connect.hdfs3.TopicPartitionWriter:615)\n", int(i / 6), (i % 6) * 10, i % 2, i % 3
        for (i = 0; i < 3; i++) printf "[2026-11-07 15:10:0%d,000] INFO [pay-sink|task-0] Starting commit and rotation for topic partition pay-0 with start offsets {pay-0=%d} and end offsets {pay-0=%d} (io.confluent.connect.hdfs3.TopicPartitionWriter:615)\n", i, i * 10, i * 10 + 9
        printf "[2026-11-07 15:11:00,000] INFO [Consumer clientId=consumer-a-1, groupId=a] Seeking to offset 12 for partition orders-0 (org.apache.kafka.clients.consumer.KafkaConsumer:1)\n"
        printf "[2026-11-07 15:11:01,000] INFO [Consumer clientId=consumer-b-2, groupId=b] Seeking to offset 7 for partition orders-1 (org.apache.kafka.clients.consumer.KafkaConsumer:1)\n"
        printf "[2026-11-07 15:11:02,000] INFO Created connector \047orders-sink\047 with id 6f1c0d2e-1a2b-4c3d-8e9f-0a1b2c3d4e5f and tags [a, b] (x.Herder:1)\n"
        printf "[2026-11-07 15:11:03,000] INFO Created connector \047pay-sink\047 with id 0b2d4f6a-8c0e-4a1b-9c2d-3e4f5a6b7c8d and tags [c] (x.Herder:1)\n"
        printf "[2026-11-07 15:11:04,000] INFO Connected to 10.0.0.1:9092 with \"secret\" and {\"a\":1} (x.Client:1)\n"
        printf "[2026-11-07 15:11:05,000] INFO Connected to 10.0.0.22:19092 with \"other\" and {\"b\":2} (x.Client:1)\n"
        for (i = 1; i <= 3; i++) printf "[2026-11-07 15:12:0%d,000] INFO [SocketServer listenerType=BROKER, nodeId=1] Failed re-authentication with /10.0.0.%d (channelId=10.0.0.9:9092-10.0.0.%d:5000%d-%d) (errorMessage={\"status\":\"Authentication failed\"}) (org.apache.kafka.common.network.Selector)\n", i, i, i, i, i
    }' > "$tmp/info.log"
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.info" "$tmp/info.log" > /dev/null 2>&1
    got=$(awk -F '\t' '$1 == "@@PGINFON@@" {print $2 "," $3 "," $4} $1 == "@@PGINFO@@" {print $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8}' "$out.info" | LC_ALL=C sort | tr '\n' ';')
    # (the first and last times are those of the first line of their minute)
    expected="2|2026-11-07T15:11:00|2026-11-07T15:11:00|2||[Consumer #] Seeking to offset # for partition orders-# (org.apache.kafka.clients.consumer.KafkaConsumer:#)|64;"
    expected+="2|2026-11-07T15:11:02|2026-11-07T15:11:02|2||Created connector '#' with id # and tags [#] (x.Herder:#)|66;"
    expected+="2|2026-11-07T15:11:04|2026-11-07T15:11:04|2||Connected to # with \"#\" and {#} (x.Client:#)|68;"
    expected+="3|2026-11-07T15:10:00|2026-11-07T15:10:00|3|pay-sink|Starting commit and rotation for topic partition pay-# with start offsets {#} and end offsets {#} (io.confluent.connect.hdfs#.TopicPartitionWriter:#)|61;"
    expected+="3|2026-11-07T15:12:01|2026-11-07T15:12:01|3||[SocketServer #] Failed re-authentication with /# (channelId=#) (errorMessage={#}) (org.apache.kafka.common.network.Selector)|70;"
    expected+="60|2026-11-07T15:00:00|2026-11-07T15:09:00|6|orders-sink|Starting commit and rotation for topic partition orders-# with start offsets {} and end offsets {} (io.confluent.connect.hdfs#.TopicPartitionWriter:#)|1;"
    expected+="72,6,0;"
    if [ "$got" != "$expected" ]
    then
        echo "❌ $awk_cmd: INFO templates of info.log: $got"
        failed=1
    fi
    got=$(awk -F '\t' '$1 == "@@PGINFO@@" && $6 == "orders-sink" {getline; print $2}' "$out.info" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ')
    if [ "$got" != "2026-11-07T15:00=6 2026-11-07T15:01=6 2026-11-07T15:02=6 2026-11-07T15:03=6 2026-11-07T15:04=6 2026-11-07T15:05=6 2026-11-07T15:06=6 2026-11-07T15:07=6 2026-11-07T15:08=6 2026-11-07T15:09=6 " ]
    then
        echo "❌ $awk_cmd: INFO template per minute of info.log: $got"
        failed=1
    fi
    # 3100 templates: the first 3000 kept, the lines of the 100 others counted apart
    awk 'BEGIN { a = "abcdefghijklmnopqrstuvwxyz"; for (i = 0; i < 3100; i++) printf "[2026-11-07 16:00:00,000] INFO Loaded plugin %s%s%s (x.Scanner:1)\n", substr(a, i % 26 + 1, 1), substr(a, int(i / 26) % 26 + 1, 1), substr(a, int(i / 676) + 1, 1) }' > "$tmp/info-cap.log"
    PATH="$bin:$PATH" bash -c 'source "$1"; PG_LOG_DIGEST_RECORDS_FILE="$2" summarize_log_errors 40 1 < "$3"' _ "$tmp/digest.sh" "$out.infocap" "$tmp/info-cap.log" > /dev/null 2>&1
    got=$(awk -F '\t' '$1 == "@@PGINFON@@" {print $2 "," $3 "," $4} $1 == "@@PGINFO@@" {n++} END {print n}' "$out.infocap" | tr '\n' ',')
    if [ "$got" != "3100,3000,100,40," ]
    then
        echo "❌ $awk_cmd: 3100 INFO templates: INFO lines, templates, lines not counted, templates written: $got instead of 3100,3000,100,40"
        failed=1
    fi
    # --since: the lines before the first time follow it, librdkafka epoch times are read, and a file without any time
    # is kept whole (and noted) rather than dropped: before, every line of it became empty and the file was reported clean
    for case in "iso||||[2026-11-08 10:00:00,000] ERROR new|  at a.b(C.java:2)|" "epoch|%3|1793896102.923|FAIL|rdkafka#producer-1| new||" \
                "none|no time on this line|ERROR nor on this one|kept whole"
    do
        kind="${case%%|*}"
        expected="${case#*|}"
        got=$(PATH="$bin:$PATH" bash -c 'source "$1"; since=2026-11-05T00:00:00; until_ts=""; since_epoch=$(window_epoch "$since"); until_epoch=""
                                         log_window_filter "$2" < "$3"' _ "$tmp/window.sh" "$out.window-$kind" "$tmp/window-$kind.log" | tr '\n' '|')
        [ -s "$out.window-$kind" ] && got="${got}kept whole"
        if [ "$got" != "$expected" ]
        then
            echo "❌ $awk_cmd: --since on window-$kind.log: $got instead of $expected"
            failed=1
        fi
    done
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
# ✂️ an overlapping copy of the same log (downloaded twice, at two times): only its lines that are not in the first one
# are analyzed; every line in the first one: skipped; the log of another worker of the same period: not an overlap
sed -n "/^LOG_TS_RE=/p;/^function log_ts_line/,/^}/p;/^function without_overlap/,/^}/p" "$root/scripts/cli/src/commands/analyze/logs.sh" > "$tmp/overlap.sh"
printf '%s\n' 'header line' '[2026-11-02 12:00:00,001] ERROR a' '  at x.y(Z.java:1)' '[2026-11-02 12:00:01,002] INFO b' '[2026-11-02 12:00:02,003] INFO c' '  continued' > "$tmp/ov-first.log"
printf '%s\n' 'header line' '[2026-11-02 12:00:01,002] INFO b' '[2026-11-02 12:00:02,003] INFO c' '  continued' '[2026-11-02 12:00:03,004] ERROR d' > "$tmp/ov-later.log"
printf '%s\n' '[2026-11-02 12:00:01,002] INFO b' '[2026-11-02 12:00:02,003] INFO c' > "$tmp/ov-inside.log"
printf '%s\n' '[2026-11-02 12:00:01,500] INFO other worker' '[2026-11-02 12:00:02,500] INFO other worker' > "$tmp/ov-other.log"
got=$(bash -c 'source "$1"; tmp_dir="$2"; same_source_file="$2/same-source"; : > "$same_source_file"; plain_logs=(); nb_overlaps=0; nb_duplicates=0
    log() { :; }
    for f in ov-first ov-later ov-inside ov-other; do without_overlap "$2/$f.log" "$f"; printf "%s=%s;" "$f" "$( [ -f "$overlap_result" ] && tr "\n" "|" < "$overlap_result" || echo "$overlap_result")"; done
    printf "%s" "$(tr "\t\n" ",;" < "$same_source_file")"' _ "$tmp/overlap.sh" "$tmp")
expected="ov-first=;ov-later=header line|[2026-11-02 12:00:03,004] ERROR d|;ov-inside=skip;ov-other=;ov-later,ov-first,3,2;ov-inside,ov-first,2,0;"
if [ "$got" != "$expected" ]
then
    echo "❌ overlapping copies: $got instead of $expected"
    failed=1
else
    echo "✅ overlapping copies of the same log"
fi
# 📦 an archive is recognized by its content: a CSV export saved as .tar is read as a file, real archives are extracted
sed -n "/^function looks_like_archive/,/^}/p" "$root/scripts/cli/src/commands/analyze/logs.sh" > "$tmp/archive.sh"
printf '%s\n' '"time","message"' '"2026-11-02 12:00:00","ERROR boom"' > "$tmp/export.tar"
mkdir -p "$tmp/arc" && printf 'x\n' > "$tmp/arc/a.log"
tar -cf "$tmp/real.tar" -C "$tmp/arc" a.log && tar -czf "$tmp/real.tar.gz" -C "$tmp/arc" a.log
( cd "$tmp/arc" && zip -q "$tmp/real.zip" a.log ) 2>/dev/null || cp "$tmp/real.tar.gz" "$tmp/real.zip"
got=$(bash -c 'source "$1"; for f in export.tar real.tar real.tar.gz real.zip; do looks_like_archive "$2/$f" && printf "%s=archive;" "$f" || printf "%s=file;" "$f"; done' _ "$tmp/archive.sh" "$tmp")
if [ "$got" != "export.tar=file;real.tar=archive;real.tar.gz=archive;real.zip=archive;" ]
then
    echo "❌ archives by content: $got"
    failed=1
else
    echo "✅ archives recognized by their content (a CSV saved as .tar is a file)"
fi
exit $failed
