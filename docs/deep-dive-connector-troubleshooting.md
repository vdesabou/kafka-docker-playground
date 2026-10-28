# 🍪 Deep dive: `playground connector diagnose` and the dead letter queue

The commands for the most common support question: "my connector doesn't work". `connector diagnose` chains status,
error digest, progress and next steps in one call. When a sink is `RUNNING` but writes nothing, the records usually
went to the dead letter queue (DLQ): `topic dlq inspect` groups them by error with the root cause and the original
offsets, and `topic dlq replay` sends them back once the cause is fixed. Takes about 15 minutes to read and run.

> [!TIP]
> In a hurry? Watch the short video session [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
> first. This page goes further: how the commands work under the hood, their gotchas, a hands-on lab and recipes for
> support repros.

| You want | Command |
| --- | --- |
| everything at once: state, errors, lag, what to do next | `playground connector diagnose [--connector <c>]` (`--since 10m`, `--max-findings 5`) |
| what is in the DLQ, and why | `playground topic dlq inspect [--connector <c> \| --topic <dlq>]` |
| only one kind of error | `… inspect --grep "Unknown magic byte"` (Java regex) |
| the groups as data | `… inspect --json` |
| what a replay would do | `playground topic dlq replay --connector <c> --dry-run` |
| send the records back to their topic | `playground topic dlq replay --connector <c>` |
| send them somewhere else | `… replay --to <topic>` (`--keep-error-headers` to keep the error headers) |

---

## 1. Mental model (the 3 things to remember)

1. **`errors.tolerance` decides between a loud failure and a silent one.** With the default
   (`errors.tolerance=none`), the first record a converter or a transform can't handle **fails the task**: the status
   shows `FAILED` and a stack trace. With `errors.tolerance=all`, the record is skipped, its offset is committed like
   any other, the task stays `RUNNING`, the lag goes to 0, and nothing reaches the destination. The skipped records
   are only visible:
   - in the DLQ, when `errors.deadletterqueue.topic.name` is set (sink connectors only),
   - in the connect log, when `errors.log.enable=true` (`errors.log.include.messages=true` adds the record).

   That's the "RUNNING but writes nothing" case: without `errors.log.enable`, the skipped records leave no ERROR in the
   log (the only one is `ERROR … Topic dlq doesn't exist. Will attempt to create topic`, once, when Connect creates the
   DLQ), and the DLQ is the only trace.

2. **The DLQ is only useful with its context headers.** With
   `errors.deadletterqueue.context.headers.enable=true`, Connect adds `__connect.errors.*` headers to each DLQ record:
   `topic`, `partition`, `offset` of the original record, `connector.name`, `task.id`, `stage`
   (`KEY_CONVERTER`, `VALUE_CONVERTER`, `HEADER_CONVERTER`, `TRANSFORMATION`, `TASK_PUT`…), `class.name`,
   `exception.class.name`, `exception.message` and `exception.stacktrace`. `dlq inspect` decodes them, `dlq replay`
   uses `__connect.errors.topic` to know where to send each record back. Without them, inspect can only say
   `no __connect.errors.* headers`, and replay needs `--to`.

   Also set `errors.deadletterqueue.topic.replication.factor=1` on a single broker: the default is 3 and the DLQ
   topic can't be created otherwise.

3. **Inspect and replay read raw bytes, once, and never delete anything.** A small Java tool (`DlqTool`, compiled once
   and cached in `~/.playground-dlq-tool`) runs in the connect container with the environment's credentials. It reads
   the DLQ from the beginning **up to the end offsets taken when it starts**, with byte-array deserializers: it works
   whatever the format (Avro, Protobuf, JSON Schema, plain JSON, garbage), and replay re-produces keys, values,
   timestamps and the other headers exactly as they are. The DLQ is never truncated: a replayed record that fails again
   is added to the DLQ a second time.

---

## 2. `connector diagnose`: four steps, never blocking

```bash
playground connector diagnose                          # every running connector
playground connector diagnose --connector orders-sink --since 10m --max-findings 5
```

| Step | Self-managed | Fully managed |
| --- | --- | --- |
| 🗺️ 1/4 status | `connector status`: connector and task states, with the trace of a failed task | same, from the Confluent Cloud API |
| 🔥 2/4 errors | `container logs -c connect --errors --since 1h`: de-duplicated ERROR/FATAL records of the **whole worker**, collapsed to their `Caused by:` chain | `connector error-recommendations`, plus a check of the service account ACLs |
| 🐢 3/4 progress | sink `RUNNING`: one `show-lag` snapshot. Sink not `RUNNING`: its committed offsets (`offsets get`). Source: its offsets | same |
| 👉 4/4 next steps | `restart` if FAILED, `resume` if PAUSED, otherwise run again / thread dump; `show-config`, `container logs --grep`, `debug log-level`, `debug thread-dump` | `show-config`, `connector logs` |

Then it writes a self-contained **HTML report** to attach to a case, `connector-diagnose-<connector>-<date>.html` in
`--output-dir` (default `/tmp/playground-diagnose`), opened in the browser from a terminal (`--no-open` to skip). It
has one section per connector:

| Section | What it shows |
| --- | --- |
| verdict, tiles, 🔎 findings | FAILED / PAUSED / UNASSIGNED / lag / clean, the root cause of each failed task (its last `Caused by:`), the known causes found in the records naming the connector (authentication, TLS, unknown magic byte…) |
| 🗺️ status | connector and tasks, worker, full trace |
| 🔥 errors | the digest of the worker, split between the records **naming the connector** (`[name\|task-0]`, `id=name-0`) and the rest of the worker, all of them, not only `--max-findings` (fully managed: the error recommendations) |
| 🐢 progress | the lag per partition with a progress bar, or the offsets as a table |
| 👉 next steps, ⚙️ configuration | the commands of step 4/4, the connector configuration with its secrets masked |

Gotchas:

- **It never follows logs and never waits for the lag to reach 0**: it's safe in scripts and for AI agents.
- **The error digest is for the whole worker**, not only this connector: an error of another connector, or of the
  worker itself, shows up too. Narrow it with `--since`.
- **A source connector has no lag**: diagnose prints its offsets. Run it twice and compare to see whether it moves.
- A clean digest doesn't mean no error: tolerated errors (`errors.tolerance=all`) are not logged without
  `errors.log.enable=true`. Look at the DLQ.
- **The lag of a new sink reads `-` for up to a minute** (`consumer lag … is not available (no offset committed yet)`):
  sink offsets are committed every `offset.flush.interval.ms` (60 s by default). Run it again a minute later.
- The exit code doesn't reflect the connector state (0, even with a FAILED task; 1 only when no connector exists):
  read the output, or use `playground connector wait --state RUNNING` in a script.
- **You often don't need to run it**: when `connector create-or-update` or `connector wait` find a FAILED connector
  or task while waiting for RUNNING, they run `connector diagnose` themselves before failing, and open its report from
  an interactive terminal (`playground config open-diagnose-report-on-failure false` to only print its path,
  `PG_SKIP_AUTO_DIAGNOSE=1` to get only the status).
- **Each run writes a new report** (the date is in the name): run it twice and open both reports to compare the
  lag or the offsets.

---

## 3. `topic dlq inspect`: from records to causes

```bash
playground topic dlq inspect --connector orders-sink          # the DLQ of that connector (errors.deadletterqueue.topic.name)
playground topic dlq inspect --topic dlq                      # a DLQ by name
playground topic dlq inspect                                  # the DLQ of the only running connector that has one
playground topic dlq inspect --topic dlq --grep "magic byte"  # only the matching errors
playground topic dlq inspect --topic dlq --json | jq '.groups[] | {count, stage, root_cause}'
```

What it prints, one block per group, most frequent first:

```text
🔢 2 record(s) of connector orders-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)
  ❌ org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic orders to Avro:
  🌱 root cause: java.lang.IllegalArgumentException: Unknown magic byte!
  📍 original records: topic orders partition 0 offsets 3..4 (2)
  📬 dlq partition 0 offsets 0..1
  🔎 sample value: {"id": 1}
🎓 replay them once the cause is fixed: playground topic dlq replay --topic dlq
```

How it works:

- **Groups** = same connector, stage, exception class **and** exception message. Two records failing with the same
  exception but a different message (a field name, a schema id) end up in two groups.
- **Root cause** = the last `Caused by:` line of `__connect.errors.exception.stacktrace` (shown only when it differs
  from the exception itself).
- **Original records**: min..max offset and count per original topic and partition. The offsets are a range, not a
  list: `3..9 (2)` means two records somewhere between 3 and 9.
- **Sample value**: the first 200 bytes of the first record of the group, non-printable bytes as `.` (an Avro or
  Protobuf payload shows its magic byte and binary fields that way).
- `--grep` is a **Java regex** matched against the exception class, message and root cause only, not the payload.
- `--json` prints `{topic, total, read, skipped_by_grep, groups: [{count, connector, stage, class, exception, message,
  root_cause, original_topics, dlq_offsets, sample_value}]}`.
- It also writes a self-contained **HTML report**, `dlq-<topic>-<date>.html` in `--output-dir` (default
  `/tmp/playground-dlq-inspect`), opened in the browser from a terminal (`--no-open` to skip). The report has:
  - the known causes with what to do (unknown magic byte, serialization error, authentication…), the same as `analyze logs`
  - a missing `__connect.errors.*` headers warning
  - when the records arrived (their timestamps)
  - one card per group: original offsets, sample value, and a `dlq replay --grep … --dry-run` for that group

Gotchas:

- **It reads the whole DLQ** (up to `--max-messages`, default 10000), including records already replayed: after a
  replay that failed again, the counts double.
- Without `--topic` or `--connector`, it uses the DLQ of the only running connector that has one, and fails when
  several connectors have one.
- **Fully managed**: the DLQ of a connector is `dlq-<lcc id>` (or its `errors.deadletterqueue.topic.name`, where
  `${connector}` stands for the lcc id). `--connector` resolves it for you.
- The first run downloads `kafka-clients` from Maven Central and compiles the tool in an `eclipse-temurin:17-jdk`
  container: slow once, then cached.
- To see the raw records: `playground topic consume -t dlq --last 1` prints the `__connect.errors.*` headers on the
  record's line (the new lines of the stack trace as `\n`), and `--json` gives them as a map:
  `playground topic consume -t dlq --json | jq -r '.headers["__connect.errors.exception.stacktrace"]'`.

---

## 4. `topic dlq replay`: once the cause is fixed

```bash
playground topic dlq replay --connector orders-sink --dry-run                       # how many records, to which topics
playground topic dlq replay --connector orders-sink                                 # back to their original topics
playground topic dlq replay --connector orders-sink --grep "magic byte" --to retry  # one kind of error, elsewhere
```

What a replayed record looks like:

| Part | After replay |
| --- | --- |
| key, value | the exact bytes of the DLQ record (which are the bytes of the original record) |
| timestamp | the DLQ record's timestamp, which Connect copied from the original record: the replayed record keeps the original time |
| headers | kept, except the `__connect.errors.*` ones (kept with `--keep-error-headers`) |
| topic | `__connect.errors.topic`, or `--to` |
| partition | **chosen by the producer** (key hash, or sticky partitioner for a null key), not the original partition |
| offset | a new one, at the end of the topic |

Gotchas:

- **Fix first, replay second.** Replaying without a fix sends the records through the same failure: they land in the
  DLQ again, now twice. `--dry-run` costs nothing.
- **Records without `__connect.errors.topic`** (context headers disabled) are skipped with a warning: use `--to`.
- **Only records already in the DLQ when the command starts are read**, so a replay can't loop on its own output, even
  with `--to` set to a topic the same connector writes to its DLQ.
- The replay produces with `acks=all`. A produce error stops it (`could not produce`, exit 1): records produced before
  the error stay produced.
- Ordering per key is kept inside one replay, but the replayed records come after the newer ones already in the topic.
- The sink commits its offsets as usual: the replayed records are new offsets, so `show-lag` shows them being
  consumed (`playground connector show-lag --connector <c> --max-wait 120`).

---

## 5. Hands-on lab (≈10 min)

A FileStream sink reading an Avro topic that also contains two plain JSON records.

```bash
playground start-environment --environment plaintext \
  --docker-compose-override-file "${PWD}/connect/connect-filestream-sink/docker-compose.plaintext.yml"
playground topic produce -t orders --nb-messages 3 < scripts/cli/predefined-schemas/avro/customer.avsc
playground topic produce -t orders --nb-messages 2 --value '{"id": %g}'           # no magic byte
```

**Step 1: the default is a loud failure**

```bash
playground connector create-or-update --connector strict-sink --no-wait << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "orders",
  "file": "/tmp/strict.txt",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
playground connector wait --connector strict-sink --state FAILED --max-wait 60
playground connector diagnose --connector strict-sink --since 5m --max-findings 3
# 🗺️  1/4 status
# strict-sink   ✅ RUNNING  0:🛑 FAILED   tasks: org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
# Caused by: org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic orders to Avro:
# Caused by: org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID
# Caused by: java.lang.IllegalArgumentException: Unknown magic byte!
# 🔥 2/4 errors: digest of connect ERROR/FATAL records since 5m (whole worker, not only this connector)
# 🔴 ERROR x1 … WorkerSinkTask{id=strict-sink-0} Task threw an uncaught and unrecoverable exception …
# 🐢 3/4 progress: committed offsets of sink strict-sink (no lag while the connector and all its tasks are not RUNNING)
# { "offsets": [] }                     <- it failed on offset 3, before its first commit
# 👉 4/4 next steps    🔥 a task or the connector FAILED … playground connector restart --connector strict-sink
# ✅ HTML report saved: /tmp/playground-diagnose/connector-diagnose-strict-sink-<date>.html   <- 🔴 Task 0 FAILED on connect:8083 …
playground connector delete --connector strict-sink
```

**Step 2: `errors.tolerance=all`, a silent one**

```bash
playground connector create-or-update --connector orders-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "orders",
  "file": "/tmp/orders.txt",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081",
  "errors.tolerance": "all",
  "errors.deadletterqueue.topic.name": "dlq",
  "errors.deadletterqueue.topic.replication.factor": "1",
  "errors.deadletterqueue.context.headers.enable": "true"
}
EOF
playground topic wait-for-records --topic dlq --min-expected-messages 2 --max-wait 120
playground connector diagnose --connector orders-sink --since 1m
# orders-sink   ✅ RUNNING  0:🟢 RUNNING
# 🔴 ERROR x1 … Topic dlq doesn't exist. Will attempt to create topic.   <- no ERROR for the 2 skipped records
# 🐢 consumer lag for 🌎onprem connector orders-sink is not available (no offset committed yet)   <- first minute
playground container exec --container connect --command "wc -l < /tmp/orders.txt"
# 3                                     <- the 3 Avro records; the 2 JSON ones went to the DLQ
```

**Step 3: what went to the DLQ, and why**

```bash
playground topic dlq inspect --connector orders-sink
# 📊 2 records in 1 group(s), most frequent first
# 🔢 2 record(s) of connector orders-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)
#   🌱 root cause: java.lang.IllegalArgumentException: Unknown magic byte!
#   📍 original records: topic orders partition 0 offsets 3..4 (2)
# ✅ HTML report saved: /tmp/playground-dlq-inspect/dlq-dlq-<date>.html   <- 🧲 Unknown magic byte: 2 record(s) in 1 group(s)
playground topic dlq inspect --topic dlq --grep 'magic byte' --json | jq -c '.groups[] | {count, stage, exception, original_topics}'
# {"count":2,"stage":"VALUE_CONVERTER","exception":"org.apache.kafka.connect.errors.DataException","original_topics":[{"topic":"orders","partition":"0","first_offset":3,"last_offset":4,"count":2}]}
```

**Step 4: the fix is a JSON sink for these records, so replay them there**

```bash
playground connector create-or-update --connector orders-json-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "orders-json",
  "file": "/tmp/orders-json.txt",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
EOF
playground topic dlq replay --connector orders-sink --to orders-json --dry-run
# 📤 2 record(s) to topic orders-json   🧪 2 records would be replayed
playground topic dlq replay --connector orders-sink --to orders-json
# ✅ 2 records replayed
playground connector show-lag --connector orders-json-sink --max-wait 90      # about a minute: the first offset commit
playground container exec --container connect --command "cat /tmp/orders-json.txt"
# {id=1}
# {id=2}
playground topic consume -t orders-json
# CreateTime:2026-10-23 12:44:32.921|Partition:0|Offset:0|Headers:NO_HEADERS|Key:null|Value:{"id": 1}
#            ^ the time of the original record           ^ error headers stripped
```

**Step 5: replay without a fix, and watch the DLQ grow**

```bash
playground topic dlq replay --connector orders-sink     # back to orders: AvroConverter fails again
playground topic wait-for-records --topic dlq --min-expected-messages 4 --max-wait 60
playground topic dlq inspect --connector orders-sink
# 🔢 4 record(s) of connector orders-sink, stage VALUE_CONVERTER (io.confluent.connect.avro.AvroConverter)
#   📍 original records: topic orders partition 0 offsets 3..6 (4)     <- the replayed copies are offsets 5..6
#   📬 dlq partition 0 offsets 0..3
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "the connector is RUNNING but nothing arrives" | `connector diagnose`: lag 0 + clean logs + a DLQ in the config → `topic dlq inspect` |
| "the task is FAILED" | `connector diagnose`: the trace in 1/4 and the digest in 2/4, then `connector restart` after the fix |
| "which records failed, and since when?" | `dlq inspect`: original topic / partition / offset range per error, `--json` for the full list |
| "`Unknown magic byte!` in the DLQ" | produce raw records to an Avro topic (`topic produce --value '{"id": %g}'`, see the [`topic produce` deep dive](/deep-dive-topic-produce.md)), sink with `AvroConverter` |
| "schema registry was down for an hour" | `playground container kill -c schema-registry`, produce, restart it, `dlq replay` (the 🩺 video session) |
| "an SMT drops records into the DLQ" | stage `TRANSFORMATION` in `dlq inspect`; test the chain with `playground connector smt test` |
| "the DLQ has no error details" | `errors.deadletterqueue.context.headers.enable=true` (`playground connector snippets --dlq` prints the DLQ block), and `--to` for replay |
| "replay only one kind of error" | `dlq replay --grep "<exception or root cause>" --dry-run`, then without `--dry-run` |
| "fully managed connector, records missing" | `connector diagnose` (error recommendations + ACL check), `dlq inspect --connector <name>` (`dlq-<lcc id>`) |

In a repro model, assert on the DLQ instead of reading it by eye:

```bash
playground topic wait-for-records --topic dlq --min-expected-messages 10 --max-wait 120
nb=$(playground topic dlq inspect --topic dlq --json | jq '[.groups[] | select(.stage == "VALUE_CONVERTER") | .count] | add // 0')
[ "$nb" == "10" ] || { logerror "❌ expected 10 value converter failures in the DLQ, got $nb"; exit 1; }
```

---

## 7. Cheat sheet

```bash
playground connector diagnose [--connector <c>] [--since 1h] [--max-findings 15] [--output-dir /tmp/playground-diagnose] [--no-open] [--verbose]
playground topic dlq inspect  [--connector <c> | --topic <dlq>] [--grep <java regex>] [--max-messages 10000] [--json] [--output-dir <dir>] [--no-open]
playground topic dlq replay   [--connector <c> | --topic <dlq>] [--to <topic>] [--grep <java regex>] [--keep-error-headers] [--dry-run]
```

```json
"errors.tolerance": "all",
"errors.deadletterqueue.topic.name": "dlq",
"errors.deadletterqueue.topic.replication.factor": "1",
"errors.deadletterqueue.context.headers.enable": "true",
"errors.log.enable": "true",
"errors.log.include.messages": "true"
```

- `errors.tolerance=none` (default): FAILED and a trace. `all`: RUNNING, lag 0, records in the DLQ.
- Context headers = error details + automatic replay target.
- Inspect groups by connector, stage, exception and message. `--grep` matches the error, not the payload.
- Replay: exact bytes, error headers stripped, new partition and offset, DLQ never truncated. Fix first.
- Diagnose and dlq inspect also write an HTML report per run (diagnose: verdict, traces, records naming the connector,
  lag, masked config; dlq inspect: known causes, arrival time, groups, replay commands).
- Sources: [`connector/diagnose.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/diagnose.sh),
  [`tools/connector-diagnose/diagnose_report.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/connector-diagnose/diagnose_report.py),
  [`tools/dlq-tool/dlq_report.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/dlq-tool/dlq_report.py),
  [`topic/dlq/inspect.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/topic/dlq/inspect.sh),
  [`topic/dlq/replay.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/topic/dlq/replay.sh),
  [`tools/dlq-tool/DlqTool.java`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/dlq-tool/DlqTool.java),
  helpers `resolve_dlq_topic` / `run_kafka_java_tool` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
- 🍪 Deep dives: [`topic consume`](/deep-dive-topic-consume.md) to read the DLQ records yourself,
  [`topic produce`](/deep-dive-topic-produce.md) to write the records that fail
- 👉 Example: [`other/reprocess-dlq-messages-with-sink-connector`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/reprocess-dlq-messages-with-sink-connector)
- 🧠 CLI reference: [playground connector diagnose](/playground%20connector%20diagnose),
  [playground topic dlq inspect](/playground%20topic%20dlq%20inspect), [playground topic dlq replay](/playground%20topic%20dlq%20replay),
  [playground connector show-lag](/playground%20connector%20show-lag), [playground connector snippets](/playground%20connector%20snippets)
