#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
source ${DIR}/lab-utils.bash

# lab of https://kafka-docker-playground.io/#/deep-dive-analyze-logs
# no container: every step runs on the samples of tools/log-analyzer/samples and on small files written here
lab_require_plaintext

work=$(mktemp -d)
report_dir="$work/reports"
trap 'rm -rf "$work"' EXIT

log "Section 2: a first run, a Connect worker log"
lab_run playground analyze logs --sample connect_task_failure --output-dir "$report_dir"
lab_expect_exit 0
lab_expect_contains "🔎 12 distinct record(s), 19 occurrence(s), in 5278 lines"
lab_expect_contains "java.sql.SQLException: ORA-01017: invalid username/password; logon denied"
lab_expect_contains "Caused by: org.apache.kafka.connect.errors.ConnectException: The capture process 'CAP\$_XOUT_1' is in an 'ABORTED' status."
lab_expect_contains "🧭 Summary: 19 occurrence(s) of 12 distinct record(s) in 1 file(s), 2026-10-14 10:03:58 → 2026-10-14 10:05:55"
lab_expect_contains "🕐 Period covered: 2026-10-14 10:01:03 → 10:05:55 (4 min 52 s) ⚠️ shorter than 10 min: the logs may not cover the incident"
lab_expect_contains "🔌 by connector: cdc-xstream-oracle-source 7 · no connector context 12"
lab_expect_contains "[HIGH] 🧨 A connector task was killed ×1 in connect-oracle-xstream-task-failure.log (first at line 5251, 2026-10-14 10:05:55)"
lab_expect_contains "[HIGH] 🔑 Authentication failure ×1 in connect-oracle-xstream-task-failure.log (first at line 9, 2026-10-14 10:03:58)"
lab_expect_contains "🌳 Root causes not explained by a known cause (top 5 of 7)"
lab_expect_contains "ERROR ×2 StreamsException: ORA-26804: Apply \"XOUT\" is disabled. · 1 connector(s): cdc-xstream-oracle-source"
lab_expect_contains "🗓️ Timeline (first 8 of 14 event(s), all files merged)"
lab_expect_contains "2026-10-14 10:04:59 🔄 rebalance of the worker group connect-cluster (connect-oracle-xstream-task-failure.log:61)"
lab_expect_contains "🔄 Restarts and rebalances (INFO lines)"
lab_expect_contains "connect-cluster: 2 worker group rebalances, 24.7/h · 2026-10-14 10:04:59 → 10:05:02"
lab_expect_not_contains "🌀 STORM"
lab_expect_contains "2026-10-14 10:03:58 🔑 Authentication failure ⬅️ 🔴 first ERROR: SQLException: ORA-01017: invalid username/password; logon denied (connect-oracle-xstream-task-failure.log:9)"
lab_expect_contains "2026-10-14 10:04:59 🔌 connector cdc-xstream-oracle-source (re)configured (connect-oracle-xstream-task-failure.log:69)"
lab_expect_contains "🔌 Connectors (1, most errors first)"
lab_expect_contains "🏷️ Kafka 8.3.2-ce (the version the components log at startup)"
lab_expect_contains "cdc-xstream-oracle-source: 1 ERROR/FATAL, 6 WARN, 🧨 1 task kill(s), 🏷️ 1.6.0 (OracleXStreamSourceConnector) · 🧨 A connector task was killed"
lab_expect_contains "👉 fixed in a newer version? playground connector-plugin changelog --connector-plugin io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector --from 1.6.0"
lab_expect_contains "⚙️ Configuration logged (24), the last dump of each: --show-config <connector|config class|client id> prints one"
lab_expect_contains "📋 For a ticket (Markdown, sanitized: review it): $report_dir/connect_task_failure-ticket.md"
lab_expect_equals "$(head -n 1 "$report_dir/connect_task_failure-ticket.md")" "## 🔥 Log analysis: sample connect_task_failure" "the summary for a ticket"
report=$(find "$report_dir" -maxdepth 1 -name "connect_task_failure-log-report.html" | head -1)
lab_expect_equals "$([ -n "$report" ] && grep -q "<h2>🗓️ Incident timeline</h2>" "$report" && echo yes)" "yes" "the report has the 🗓️ incident timeline"
lab_expect_equals "$([ -n "$report" ] && grep -q "class='tl-chart'" "$report" && grep -q "class='mono tl-delta'" "$report" && echo yes)" "yes" "the timeline has its chart and its Δ column"
lab_expect_equals "$(grep -q "<h2>🔌 Connectors (1)</h2>" "$report" && echo yes)" "yes" "the report has the 🔌 connector cards"

log "Section 2: a worker with many connectors"
lab_run playground analyze logs --sample connect_many_connectors --output-dir "$report_dir"
lab_expect_exit 0
lab_expect_contains "🛟 3 connector(s) below the minimum version supported on CP 8.1: s3-sink 10.5.13 < 11.0.2, http-sink 1.7.6 < 1.7.10, jdbc-oracle-sink 10.7.4 < 10.8.4"
lab_expect_contains "[HIGH] 🧨 A connector task was killed ×3 in connect-many-connectors.log (first at line 179, 2026-11-06 09:02:20)"
lab_expect_contains "🔌 Connectors (8, most errors first)"
report=$(find "$report_dir" -maxdepth 1 -name "connect_many_connectors-log-report.html" | head -1)
lab_expect_equals "$([ -n "$report" ] && grep -q "eos-banner" "$report" && grep -q "conn-support bad" "$report" && echo yes)" "yes" "the report has the ⛔ banner and the 🛟 lines of the cards"

log "Section 3: a JSON export of a log console"
cat > "$work/cloudwatch.json" << 'EOF'
[
  {"@timestamp": "2026-11-06 10:00:02.000", "@message": "[2026-11-06 10:00:02,000] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)\norg.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler\nCaused by: org.apache.kafka.common.errors.SerializationException: Unknown magic byte!"},
  {"@timestamp": "2026-11-06 10:00:01.000", "@message": "[2026-11-06 10:00:01,000] INFO [s3-sink|task-0] Started (io.confluent.connect.s3.S3SinkTask)"}
]
EOF
lab_run bash -c "cd '$work' && playground analyze logs -f cloudwatch.json --output-dir '$report_dir'"
lab_expect_contains "🔄 cloudwatch.json: JSON export of 2 log events (633 B), analyzed as log lines (oldest first)"
lab_expect_contains "[HIGH] 🧨 A connector task was killed ×1 in cloudwatch.json (first at line 2, 2026-11-06 10:00:02)"
lab_expect_contains "[HIGH] 🧯 errors.tolerance exceeded ×1 in cloudwatch.json (first at line 2, 2026-11-06 10:00:02)"
lab_expect_contains "[HIGH] 🧲 Unknown magic byte ×1 in cloudwatch.json (first at line 2, 2026-11-06 10:00:02)"

log "Section 3: the non-Java clients"
lab_run playground analyze logs --sample kafka_clients --output-dir "$report_dir"
lab_expect_contains "🧭 Summary: 208 occurrence(s) of 23 distinct record(s) in 12 file(s), 2026-11-05 16:28:22 → 2026-11-05 16:33:40"
lab_expect_contains "[HIGH] 🔌 Connection failure ×195 in 7 files (first at python-producer.log line 1, 2026-11-05 16:28:22)"
lab_expect_contains "[HIGH] ⚙️ Invalid client configuration ×1 in python-producer.log (first at line 34)"
lab_expect_contains "[HIGH] ⌛ Records not delivered in time ×5 in 2 files (first at python-producer.log line 27)"
lab_expect_contains "[HIGH] 🗺️ Topic not found in the metadata ×2 in 2 files (first at rust-producer.log line 1)"
lab_expect_contains "[MEDIUM] 📥 Producer buffer full ×1 in synthetic-crashes/python-logging.log (first at line 2, 2026-11-05 16:30:02)"

log "Section 3: Kafka Streams"
lab_run playground analyze logs --sample kafka_streams --output-dir "$report_dir"
lab_expect_contains "🌊 application streams-serde-errors-fail-on-poison-pill (Kafka Streams 4.4.0): 3 instance(s)"
lab_expect_contains "streams.log ERROR 15:19:21 3 (0.5s) 1 DEAD 0_0 - -"
lab_expect_contains "streams2.log RUNNING 15:19:05 3 (0.5s) 1 RUNNING 0_1 - -"
lab_expect_contains "streams3.log RUNNING 15:19:06 2 (2.7s) 1 RUNNING 0_2 - -"
lab_expect_contains "❌ streams.log: the client is ERROR since 2026-11-05 15:19:21"

log "Section 4: errors right after a change"
cat > "$work/change.log" << 'EOF'
[2026-11-06 10:00:00,000] INFO [s3-sink|worker] SinkConnectorConfig values: 
	connector.class = io.confluent.connect.s3.S3SinkConnector
	flush.size = 100
	name = s3-sink
	tasks.max = 1

[2026-11-06 10:00:05,000] INFO [s3-sink|task-0] all good (io.confluent.connect.s3.S3SinkTask)
[2026-11-06 10:20:00,000] INFO [s3-sink|worker] SinkConnectorConfig values: 
	connector.class = io.confluent.connect.s3.S3SinkConnector
	flush.size = 100000
	name = s3-sink
	tasks.max = 1

[2026-11-06 10:21:30,000] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)
    org.apache.kafka.connect.errors.ConnectException: java.lang.OutOfMemoryError: Java heap space
[2026-11-06 10:40:00,000] ERROR [other-sink|task-0] unrelated error in another connector (com.acme.Other)
EOF
lab_run playground analyze logs -f "$work/change.log" --output-dir "$report_dir"
lab_expect_contains "🔗 Errors right after a change (1)"
lab_expect_contains "⏱️ 1 min 30 s after ⚙️ SinkConnectorConfig: flush.size 100 → 100000"
lab_expect_not_contains "unrelated error in another connector (com.acme.Other) ⏱️"

log "Section 5: one connector, its configuration"
lab_run playground analyze logs --sample connect_task_failure --connector cdc-xstream-oracle-source --output-dir "$report_dir"
lab_expect_contains "🧭 Summary (--connector cdc-xstream-oracle-source): 7 occurrence(s) of 4 distinct record(s) in 1 file(s), 2026-10-14 10:05:02 → 2026-10-14 10:05:55"
lab_run playground analyze logs --sample connect_task_failure --until "2026-10-14 10:04" --output-dir "$report_dir"
lab_expect_contains "⏱️ Only the lines logged before 2026-10-14 10:04:00 (--since / --until)"
lab_expect_contains "🔎 2 distinct record(s), 2 occurrence(s), in 5278 lines"
# the epoch times of the librdkafka lines are read; a file without any time is analyzed whole, with a warning
printf '%s\n' '%3|1793896102.923|FAIL|rdkafka#producer-1| [thrd:broker:9092/1]: broker:9092/1: Connect to ipv4#10.0.0.1:9092 failed: Connection refused' > "$work/client.log"
lab_run playground analyze logs -f "$work/client.log" --since "2026-11-05" --output-dir "$report_dir"
lab_expect_contains "🔎 1 distinct record(s), 1 occurrence(s), in 1 lines"
printf '%s\n' 'ERROR a line without any time' > "$work/notime.log"
lab_run playground analyze logs -f "$work/notime.log" --since "2026-11-05" --output-dir "$report_dir"
lab_expect_contains "no time found in its lines (YYYY-MM-DD hh:mm:ss, librdkafka epoch), --since / --until not applied: the whole file is analyzed"
lab_expect_contains "🔎 1 distinct record(s), 1 occurrence(s), in 1 lines"

log "Section 5: members removed by the group coordinator"
cat > "$work/coordinator.log" << 'EOF'
[2026-11-07 10:30:00,000] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=7] [GroupId connect-s3-sink] Member connector-consumer-s3-sink-0-77aa has failed, removing it from the group. (org.apache.kafka.coordinator.group.GroupMetadataManager)
[2026-11-07 10:31:05,000] INFO [GroupCoordinator 1]: Group connect-s3-sink removed dynamic members who haven't joined: Set(connector-consumer-s3-sink-1-88bb) (kafka.coordinator.group.GroupCoordinator)
[2026-11-07 10:32:00,000] ERROR [ReplicaManager broker=1] Error processing append operation on partition orders-0 (kafka.server.ReplicaManager)
EOF
lab_run playground analyze logs -f "$work/coordinator.log" --output-dir "$report_dir"
lab_expect_contains "🚪 members of group connect-s3-sink removed by the coordinator: session timeout (no heartbeat)"
lab_expect_contains "🚪 members of group connect-s3-sink removed by the coordinator: rebalance timeout (did not rejoin)"
lab_expect_contains "connect-s3-sink: 2 group members removed by the coordinator"
lab_run playground analyze logs --sample connect_task_failure --show-config cdc-xstream-oracle-source --output-dir "$report_dir"
lab_expect_contains "⚙️ SourceConnectorConfig [cdc-xstream-oracle-source|worker] cdc-xstream-oracle-source · 24 keys · connect-oracle-xstream-task-failure.log:69 (2026-10-14 10:04:59)"
lab_expect_contains "config.action.reload = restart"
lab_expect_contains "connector.class = io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector"

log "Section 5: config lint"
cat > "$work/lint.log" << 'EOF'
[2026-11-06 10:00:00,000] INFO [s3-sink|worker] SinkConnectorConfig values: 
	connector.class = io.confluent.connect.s3.S3SinkConnector
	errors.deadletterqueue.topic.name = 
	errors.log.enable = false
	errors.tolerance = all
	name = s3-sink
	topics = [orders]

[2026-11-06 10:00:01,000] INFO [s3-sink|task-0] ConsumerConfig values: 
	auto.offset.reset = earliest
	client.id = connector-consumer-s3-sink-0
	max.poll.interval.ms = 300000
	max.poll.records = 20000

[2026-11-06 10:00:02,000] INFO [jdbc-src|task-0] ProducerConfig values: 
	acks = 1
	client.id = connector-producer-jdbc-src-0

[2026-11-06 10:00:03,000] INFO [jdbc-src|worker] ProducerConfig values: 
	acks = 1
	client.id = jdbc-src-license-manager

[2026-11-06 10:05:00,000] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Commit of offsets threw an unexpected exception: org.apache.kafka.clients.consumer.CommitFailedException: Commit cannot be completed since the group has already rebalanced (org.apache.kafka.connect.runtime.WorkerSinkTask)
EOF
lab_run playground analyze logs -f "$work/lint.log" --output-dir "$report_dir"
lab_expect_contains "🧪 Config lint (4, the configuration logged at startup)"
lab_expect_contains "[MEDIUM] jdbc-src: acks=1 → the source producer does not wait for all the in-sync replicas"
lab_expect_contains "[MEDIUM] s3-sink: errors.tolerance=all → bad records are skipped and lost: no dead letter queue"
lab_expect_contains "[MEDIUM] s3-sink: max.poll.records=20000 → 20000 records per poll with max.poll.interval.ms=300000"
lab_expect_contains "[LOW] s3-sink: errors.log.enable=false"
lab_expect_not_contains "license-manager: acks"

log "Section 6: did the fix work? --compare"
lab_run playground analyze logs --sample compare_fix --output-dir "$report_dir"
lab_expect_contains "🔁 Compared with tools/log-analyzer/samples/compare/before.log: 1 new root cause(s), 1 growing, 0 shrinking, 3 gone, 6 unchanged · new known cause(s): 🔌 Connection failure · gone: 🤺 Producer fenced (transactions, exactly-once), 🚦 Throttled by the external system, 🚧 Request refused by a broker policy"
lab_expect_contains "FATAL 0 → 0 · ERROR 6 → 5 · WARN 4 → 9 · period 9 min → 9 min"
lab_expect_contains "🆕 new 0 → 1 SQLRecoverableException: IO Error: Connection reset by peer"
lab_expect_contains "📈 growing 1 → 7 RebalanceInProgressException: Offset commit cannot be completed since the consumer is undergoing a rebalance"
lab_expect_contains "✅ gone 1 → 0 ProducerFencedException:"
lab_expect_contains "✅ gone 1 → 0 PolicyViolationException: Topic replication factor must be 3"
lab_expect_contains "✅ gone 1 → 0 AmazonS3Exception: Please reduce your request rate."

grep -v "SQLRecoverableException\|10:06:0[3-6]" "${DIR}/../../tools/log-analyzer/samples/compare/after.log" | sed 's/2026-11-06/2026-11-07/g' > "$work/day3.log"
lab_run bash -c "cd '${DIR}/../..' && playground analyze logs -f '$work/day3.log' --compare tools/log-analyzer/samples/compare/before.log --compare tools/log-analyzer/samples/compare/after.log --output-dir '$report_dir'"
lab_expect_contains "📈 Trend over 3 inputs (oldest first: tools/log-analyzer/samples/compare/before.log → tools/log-analyzer/samples/compare/after.log → "
lab_expect_contains "FATAL 0 → 0 → 0 · ERROR 6 → 5 → 4 · WARN 4 → 9 → 5"
lab_expect_contains "1 → 7 → 3 RebalanceInProgressException: Offset commit cannot be completed since the consumer is undergoing a rebalance"

log "Section 7: JSON for scripts and agents"
lab_run bash -c "playground analyze logs --sample support_bundle --json 2>/dev/null | jq -r '.known_causes[] | \"\(.severity) \(.title) ×\(.occurrences)\"'"
lab_expect_contains "HIGH 🧨 A connector task was killed ×1"
lab_expect_contains "HIGH 🔑 Authentication failure ×1"
lab_run bash -c "playground analyze logs --sample support_bundle --json 2>/dev/null | jq -c '.connectors[] | {connector, by_level, task_killed}'"
lab_expect_contains '{"connector":"cdc-xstream-oracle-source","by_level":{"FATAL":0,"ERROR":1,"WARN":6},"task_killed":1}'

log "Section 8: before sharing, --sanitize"
cat > "$work/secrets.log" << 'EOF'
[2026-11-06 10:00:00,000] ERROR [jdbc-sink|task-0] Login failed for user 'app' to jdbc:postgresql://db.acme.corp:5432/orders with sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="app" password="s3cr3t!"; from 10.20.30.40 (io.confluent.connect.jdbc.sink.JdbcSinkTask)
EOF
lab_run playground analyze logs -f "$work/secrets.log" --sanitize --output-dir "$report_dir"
lab_expect_contains "jdbc:postgresql://<HOST-1>:5432/orders with sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"app\" password=<REDACTED>; from <IP-1>"
lab_expect_contains "🔒 Sanitized (best effort, review before sharing): 2 secret(s), 1 IP(s), 1 hostname(s), 0 email(s), 0 LDAP DN(s) (--sanitize)"
lab_expect_not_contains "s3cr3t!"
lab_expect_not_contains "10.20.30.40"

log "Section 9, step 5: a truncated download"
{ for i in $(seq 1 3000); do echo "2026-11-06 10:00:00,000 INFO [s3-sink|task-0] batch $i written"; done
  echo "2026-11-06 10:59:00,000 ERROR [s3-sink|task-0] the error you are looking for"; } | gzip > "$work/full.log.gz"
head -c 2000 "$work/full.log.gz" > "$work/partial.log.gz"
lab_run bash -c "cd '$work' && playground analyze logs -f partial.log.gz --output-dir '$report_dir'"
lab_expect_contains "⚠️ partial.log.gz: truncated or corrupt gzip, read only up to the error (partial.log.gz: unexpected end of file)"
lab_expect_contains "⚠️ no ERROR/FATAL/WARN record found in 1 file(s), but 1 input(s) were not fully read: the missing part may hold errors"
lab_expect_not_contains "✅ no ERROR/FATAL/WARN record found"

log "✅ all the outputs quoted by the page were found"
