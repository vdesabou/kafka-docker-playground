# 🍪 Deep dive: `playground analyze logs`

A customer sends a 2 GB support bundle, a CloudWatch export, the logs of three Kafka Streams instances, or the output
of a Python producer. `playground analyze logs` reads all of it and tells you **what is failing, since when, where, and
what to do**: a digest in the terminal, a self-contained HTML report you can send to a colleague, and a JSON for
scripts and agents. With `--compare`, it also tells you **whether the fix worked**.

Takes about 20 minutes to read and run. Everything below runs on samples shipped with the playground: no container,
no Confluent Cloud, nothing to set up.

> [!TIP]
> 🎬 The video session [🔁 Did the fix work? Analyze the logs before and after it](/sessions?id=🔁-did-the-fix-work-analyze-the-logs-before-and-after-it)
> shows `--compare`, the summary, the timeline and a truncated download in 3 minutes, and
> [🕵️ A connector failed: read the logs, live or from a customer bundle](/sessions?id=🕵️-a-connector-failed-read-the-logs-live-or-from-a-customer-bundle)
> `analyze logs` on a customer bundle. Live containers have their own page:
> [`container logs`](deep-dive-container-logs.md) (`--errors` is the same digest on a running container).

| You want | Command |
| --- | --- |
| what is failing in a bundle, a folder, a file | `playground analyze logs -f <path>` (repeat `-f`) |
| only one connector | `… --connector <name>` (`--with-worker` to keep the worker records) |
| the configuration a component logged at startup | `… --show-config <connector\|config class\|client id>` |
| whether the fix worked | `playground analyze logs -f <after> --compare <before>` |
| something to paste in a ticket outside Confluent | `… --sanitize` |
| JSON for `jq`, a script or an agent | `… --json [--json-sections summary,known_causes,timeline]` |
| to try it now | `playground analyze logs --sample support_bundle` |

📊 **Example reports** (open them, they are the real output of the samples):
[🔥 a support bundle](reports/logs.html) ·
[🔌 a Connect worker](reports/logs-connect.html) ·
[🧰 the non-Java clients](reports/logs-clients.html) ·
[🔁 a comparison before / after a fix](reports/logs-compare.html) ·
[🌊 Kafka Streams](reports/kafka-streams.html). All the reports of the playground are in the [📊 reports gallery](reports.md).

---

## 1. Mental model (the 4 things to remember)

1. **A digest, not a grep.** Every record with an explicit level (`ERROR`, `[ERROR]`, `level=error`, a librdkafka
   `%3|`, a Python traceback, a Go panic…) is kept, de-duplicated with an occurrence count, and its stack trace is cut
   to its `Caused by:` chain plus 3 frames of the deepest cause. 1.1 million `failed authentication` lines of 321
   connectors become **one** record with a count. INFO lines that merely contain "error" never count.
2. **Known causes first.** About 50 known causes (task killed, `errors.tolerance` exceeded, authentication, TLS, wrong
   `security.protocol`, unknown magic byte, fenced producer, rebalances, throttling, records not delivered in time…)
   are recognized and come with **what to do**, often the `playground` command that checks it. Everything else is in
   the 🌳 root causes, grouped by deepest exception.
3. **The HTML report is the deliverable.** The terminal digest is bounded (`--max-findings` per file); the report holds
   **every** record, a timeline of all the files, a card per connector, filters, links to each line of each file, and
   a 📤 Share panel. The filters are kept in the URL: 🔗 **Link to this view** points a colleague at one burst of one
   connector.
4. **No finding is not a verdict.** Before saying "the logs are clean", check the 🕐 **period covered** (orange under 10
   minutes: the bundle may not contain the incident) and the ⚠️ **Not fully read** inputs (a truncated download). With
   no finding, an 🔭 overview says what the logs contain and what to ask for next.

---

## 2. A first run: a Connect worker log

```bash
playground analyze logs --sample connect_task_failure
```

The sample is the log of a Connect worker running the Oracle XStream source connector: a wrong password, an outbound
server that does not exist, then a task failing after the outbound server was stopped. First the digest of each file,
FATAL then ERROR then WARN, each record with its count and its first / last line:

```text
🔥 ERROR/FATAL digest for …/tools/log-analyzer/samples/connect-oracle-xstream-task-failure.log
🔎 12 distinct record(s), 19 occurrence(s), in 5278 lines

🔴 ERROR x1 (first seen line 9, last seen line 9)
[2026-10-14 10:03:58,508] ERROR Failed testing source connection for {os.timezone=UTC, hostname=oracle, password=********, …
    java.sql.SQLException: ORA-01017: invalid username/password; logon denied
…
🔴 ERROR x1 (first seen line 5251, last seen line 5251)
[2026-10-14 10:05:55,629] ERROR [cdc-xstream-oracle-source|task-0] WorkerSourceTask{id=cdc-xstream-oracle-source-0} Task threw an uncaught and unrecoverable exception. …
    org.apache.kafka.connect.errors.ConnectException: An exception occurred in the change event producer. This connector will be stopped.
    Caused by: org.apache.kafka.connect.errors.ConnectException: The capture process 'CAP$_XOUT_1' is in an 'ABORTED' status. …
```

Then the 🧭 **summary**, what the HTML report says first, bounded so that it fits a screen (and an agent's context):

```text
🧭 Summary: 19 occurrence(s) of 12 distinct record(s) in 1 file(s), 2026-10-14 10:03:58 → 2026-10-14 10:05:55
   🕐 Period covered: 2026-10-14 10:01:03 → 10:05:55 (4 min 52 s) ⚠️ shorter than 10 min: the logs may not cover the incident
   🏷️ Kafka 8.3.2-ce (the version the components log at startup)
   🔌 by connector: cdc-xstream-oracle-source 7 · no connector context 12
🧠 Known causes
   [HIGH] 🧨 A connector task was killed ×1 in connect-oracle-xstream-task-failure.log (first at line 5251, 2026-10-14 10:05:55)
      → it stays FAILED until it is restarted: fix the cause (the exception chain of the record), then playground connector restart --connector <connector>
   [HIGH] 🔑 Authentication failure ×1 in connect-oracle-xstream-task-failure.log (first at line 9, 2026-10-14 10:03:58)
      → check the credentials (user, password, API key, keytab) of the client or of the external system
🌳 Root causes not explained by a known cause (top 5 of 7)
   ERROR ×2 StreamsException: ORA-26804: Apply "XOUT" is disabled. · 1 connector(s): cdc-xstream-oracle-source
   …
🗓️ Timeline (first 8 of 14 event(s), all files merged)
   2026-10-14 10:03:58 🔑 Authentication failure ⬅️ 🔴 first ERROR: SQLException: ORA-01017: invalid username/password; logon denied (connect-oracle-xstream-task-failure.log:9)
   2026-10-14 10:03:59 🔴 first ERROR: The outbound server 'XOUT_MISSING' is not valid. …
   2026-10-14 10:04:59 🔄 rebalance of the worker group connect-cluster (connect-oracle-xstream-task-failure.log:61)
   2026-10-14 10:04:59 🔌 connector cdc-xstream-oracle-source (re)configured (connect-oracle-xstream-task-failure.log:69)
   …
🔌 Connectors (1, most errors first)
   cdc-xstream-oracle-source: 1 ERROR/FATAL, 6 WARN, 🧨 1 task kill(s), 🏷️ 1.6.0 (OracleXStreamSourceConnector) · 🧨 A connector task was killed
      👉 fixed in a newer version? playground connector-plugin changelog --connector-plugin io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector --from 1.6.0
🔄 Restarts and rebalances (INFO lines)
   connect-cluster: 2 worker group rebalances, 24.7/h · 2026-10-14 10:04:59 → 10:05:02
   cflt-schemahistory: 10 consumer group rejoins, 123.3/h · consumer pro-actively leaving the group · 2026-10-14 10:05:02 → 10:05:54
   …
⚙️ Configuration logged (24), the last dump of each: --show-config <connector|config class|client id> prints one
```

Read it top-down: **4 min 52 s of logs** (too short to be sure the bundle holds the cause: ask for more), **a task was
killed**, and the 🗓️ timeline says what came first: the wrong password at 10:03:58, the missing outbound server one
second later, then the connector reconfigured twice. The 🔌 card says which **version** of the connector runs (read from
`Instantiated connector … with version 1.6.0`) with the command that lists what changed since: here 1.6.1 fixes a
`NullPointerException` of the task. The report of this run is
[🔌 a Connect worker](reports/logs-connect.html).

---

## 3. What it reads

Give it anything: `-f` takes files, folders and archives, repeated as many times as needed.

| Input | What happens |
| --- | --- |
| a folder | scanned recursively, sorted; `__MACOSX/`, `.DS_Store` ignored; a copy of a file already analyzed is skipped (`⏭️ … same content as …`) |
| `.zip`, `.tar`, `.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, `.7z` | extracted to a temporary folder, nested archives too (`.7z` needs `bsdtar` or 7-Zip). An archive that does not fully extract is reported ⚠️ |
| `.gz` | decompressed on the fly; a truncated one (a partial download) is read up to the error and reported ⚠️ |
| a JSON export of log events: CloudWatch Logs Insights, CloudWatch events, Elasticsearch / OpenSearch hits (`_source` or `fields`), the Loki query API, structured JSON logs (logback, pino, bunyan, GELF: numeric levels too) | converted back to log lines, **oldest first**, stack traces below their event, then digested like a log file |
| a CSV export (Kibana / OpenSearch Discover, Splunk `_time,_raw`, Datadog, Grafana) | one event per row, converted the same way |
| JSON lines whatever the extension (a fluentd / Kubernetes dump saved as `.log`) | detected and streamed: 2.4 GB in about 10 s |
| `journalctl` exports | the `Nov 03 18:29:20 host connect[1080]:` prefix is skipped to find the log4j timestamp |
| the logs of the C/C++, Python, Go, .NET, JavaScript and Rust clients | librdkafka `%3\|…\|FAIL\|` lines, Python tracebacks, Go and Rust panics, .NET `fail:` / `crit:` and inner exceptions, KafkaJS errors |
| Kafka Streams logs (`stream-client [`, `stream-thread [`) | the digest, plus a 🌊 **Kafka Streams** section: state of each instance over time, rebalances, tasks, restores |
| a CFK support bundle | analyzed as a whole by the CFK analyzer: pods, custom resources, events, versions, recent changes, see [the CFK deep dive](deep-dive-cfk.md) (`--logs-only` for the plain digest) |
| `.properties`, connector JSON (`/connectors?expand=info`) | shown in the ⚙️ configuration of the report |
| a binary file | skipped, counted in the last line |

### A JSON export of a log console

```bash
cat > cloudwatch.json << 'EOF'
[
  {"@timestamp": "2026-11-06 10:00:02.000", "@message": "[2026-11-06 10:00:02,000] ERROR [s3-sink|task-0] WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask)\norg.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler\nCaused by: org.apache.kafka.common.errors.SerializationException: Unknown magic byte!"},
  {"@timestamp": "2026-11-06 10:00:01.000", "@message": "[2026-11-06 10:00:01,000] INFO [s3-sink|task-0] Started (io.confluent.connect.s3.S3SinkTask)"}
]
EOF
playground analyze logs -f cloudwatch.json
```

```text
ℹ️ 🔄 cloudwatch.json: JSON export of 2 log events (633 B), analyzed as log lines (oldest first)
…
🧠 Known causes
   [HIGH] 🧨 A connector task was killed ×1 in cloudwatch.json (first at line 2, 2026-11-06 10:00:02)
   [HIGH] 🧯 errors.tolerance exceeded ×1 in cloudwatch.json (first at line 2, 2026-11-06 10:00:02)
   [HIGH] 🧲 Unknown magic byte ×1 in cloudwatch.json (first at line 2, 2026-11-06 10:00:02)
```

The console exported the newest event first; the digest puts it back in order, and the stack trace inside the JSON
string is read as a stack trace.

### The non-Java clients

```bash
playground analyze logs --sample kafka_clients
```

The logs of the C/C++, Python, Go, .NET, JavaScript, KafkaJS and Rust producers of `other/client-*`, against a broker
that refuses connections or does not resolve:

```text
🧭 Summary: 208 occurrence(s) of 23 distinct record(s) in 12 file(s), 2026-11-05 16:28:22 → 2026-11-05 16:33:40
…
🧠 Known causes
   [HIGH] 🔌 Connection failure ×195 in 7 files (first at python-producer.log line 1, 2026-11-05 16:28:22)
   [HIGH] ⚙️ Invalid client configuration ×1 in python-producer.log (first at line 34)
   [HIGH] ⌛ Records not delivered in time ×5 in 2 files (first at python-producer.log line 27)
   [HIGH] 🗺️ Topic not found in the metadata ×2 in 2 files (first at rust-producer.log line 1)
   [MEDIUM] 📥 Producer buffer full ×1 in synthetic-crashes/python-logging.log (first at line 2, 2026-11-05 16:30:02)
```

[🧰 Its report](reports/logs-clients.html).

### Kafka Streams

```bash
playground analyze logs --sample kafka_streams
```

```text
🌊 application streams-serde-errors-fail-on-poison-pill (Kafka Streams 4.4.0): 3 instance(s)
  INSTANCE      STATE    SINCE     REBALANCES  THREADS    ACTIVE TASKS  STANDBY TASKS  NOT RESTORED
  streams.log   ERROR    15:19:21  3 (0.5s)    1 DEAD     0_0           -              -
  streams2.log  RUNNING  15:19:05  3 (0.5s)    1 RUNNING  0_1           -              -
  streams3.log  RUNNING  15:19:06  2 (2.7s)    1 RUNNING  0_2           -              -
  ❌ streams.log: the client is ERROR since 2026-11-05 15:19:21
```

One instance is ERROR with a dead thread after a poison pill; the HTML report draws the state of each instance over
time ([🌊 the same view](reports/kafka-streams.html), from `playground streams status`).

---

## 4. The HTML report, section by section

Written in `--output-dir` (`./log-analysis-output` by default) as `<first input>-log-report.html`, opened in the
browser from a terminal, with a page per file with findings in `<report>-files/` (📄 links open the file at the line,
✏️ opens it in your editor). Open [🔥 the support bundle report](reports/logs.html) next to this table:

| Section | What it answers |
| --- | --- |
| verdict and tiles | the one-line diagnosis, 🕐 the period covered (orange under 10 min), files, distinct records, occurrences by level |
| ⚠️ not fully read | which inputs could not be read completely (truncated `.gz`, archive not extracted): the findings only cover the rest |
| 🔁 comparison | with `--compare`: what is new, gone, growing or shrinking (section 6) |
| 🎚️ filter bar | levels, components, connector, search, period: everything below follows it, and the URL keeps it |
| 🔎 findings | the known causes with what to do and their exception chains, then the most frequent errors no known cause explains; each card says how much of it is in the current selection |
| 🗓️ incident timeline | *what happened first?*: all files merged, the first occurrence of each error and known cause, restarts, connectors reconfigured, config changed between restarts |
| 🔄 restarts and rebalances | from the INFO lines (the digest only keeps ERROR / WARN): the rebalances of the worker groups, the rejoins of the consumer groups with their reason, the connectors and tasks started, the workers and brokers (re)started, each counted with its rate per hour. 🌀 **storm**: 10 or more at 6 or more per hour (a consumer that leaves on purpose, `pro-actively leaving the group`, is not one); also on the 🔌 cards and in the 🗓️ timeline |
| 🔌 connectors | a card per connector, the 30 with the most errors first (show the others): errors, task kills, known causes, configuration, keys changed; ▶ only this connector keeps its card only (⤺ for all of them), the search filters the cards |
| 📈 occurrences over time | drag to zoom down to the second; an error repeated all day is spread over the day (sampled, counted with its weight) |
| 🌳 all root causes | every distinct error, by deepest exception, linked to the finding that explains it |
| 🗂️ files and 🕰️ log coverage | per file and per folder of rotated logs, with the hours a folder has no log |
| 📄 records of each file | every distinct record, its exception chain colored, 📄 / ✏️ to the line |
| ⚙️ configuration | the configs logged at startup (one block per config class, the keys that differ between dumps, the keys changed between restarts) and the `.properties` / connector JSON of the input |
| 📤 Share | the `.zip` of the report and its pages, the summary to paste, **📋 Copy for a ticket** (Markdown, always sanitized), an email, the sanitization state |

### The filters, the search, and links to a view

- **Levels** (`💀 FATAL`, `🔴 ERROR`, `🟠 WARN`), **components** (`🔌 Connect`, `🗄️ Kafka`, `📡 Clients`…, from the file
  names: `server.log` → Kafka), **connector** (the `[connector|task-0]` context of the line) and **period** (drag over
  📈) combine; the charts, root causes, files, records and timeline follow.
- **Search**: words that must all be there, `-word` to exclude, `"a phrase"`, `/regex/`. The matches are highlighted.
  `ora- -xout` keeps the Oracle errors that do not mention the outbound server; `/ORA-0101[0-9]/` the login errors.
- **🔗 Link to this view** copies the URL, which holds the filters:
  `…/support_bundle-log-report.html#pg:comp=connect&q=ora-&t=1791972240-1791972360` opens the report on the Connect
  files, the Oracle errors, between 10:04 and 10:06.
- The component you pick is remembered for the next reports; a link wins over it.

> [!NOTE]
> The 🔎 findings are never rewritten by a filter: they are the diagnosis of the bundle. Each one says how much of it is
> in the selection (`▸ 340 of 1200 occurrence(s) here`), and the ones with nothing in it are hidden, with a
> `🙈 5 finding(s) with nothing in this selection hidden` **show them** to bring them back.

Times are shown **as written in the logs**, whatever the time zone of your browser; when the files mix offsets
(`+02:00` Connect logs and `Z` broker logs), they are converted to UTC so that the files line up (`🌐 UTC` on the 🕐
tile).

---

### 🔗 Errors right after a change

"It broke after we changed something": an ERROR / FATAL that first appears less than 10 minutes after a config key
changed (between two dumps of the same config) or a worker / broker restarted, of the same connector when both have one,
is linked to that change, in the 🗓️ timeline (🔗), the terminal summary and the summary for a ticket:

```bash
cat > change.log << 'EOF'
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
playground analyze logs -f change.log
```

```text
🔗 Errors right after a change (1)
   2026-11-06 10:21:30 💥 OutOfMemoryError · 🧨 A connector task was killed ⬅️ 🔴 first ERROR: WorkerSinkTask{id=s3-sink-0} Task threw an uncaught and unrecoverable exception.  ⏱️ 1 min 30 s after ⚙️ SinkConnectorConfig: flush.size 100 → 100000
```

The error of `other-sink` 20 minutes later is not linked: another connector, and too late. A connector created is not a
change (everything after it would follow it), nor the first start of a worker.

### 🔭 No finding, ⏳ large inputs, ☸️ bundles inside bundles

- **No finding**: instead of a bare ✅, an 🔭 **overview** of what the logs contain (lines, period and levels of each
  file, the 10 most frequent messages with numbers and ids masked, the top loggers) and 👉 what to ask for next (a
  longer window, the logs of the component that fails, a new export of a console cut at its size limit). Also the 🔭
  Overview section of the report and `.overview` of `--json`.
- **Large inputs**: from 20 MB, a progress bar in the terminal and, in an interactive terminal, the report opens right
  away as a progress page (the file being read, the whole input, speed, ETA) that becomes the report. 2.4 GB of JSON
  lines take about 30 s.
- **CFK support bundles** found inside the input are analyzed by the CFK analyzer, 4 at a time
  (`PLAYGROUND_CFK_PARALLELISM`), and linked from the log report in a ☸️ section: one browser tab.
- **Copies** of a file or of a bundle (an archive next to its extracted folder) are analyzed once.

---

## 5. One connector, its configuration

On a worker with 300 connectors, keep one:

```bash
playground analyze logs --sample connect_task_failure --connector cdc-xstream-oracle-source
```

```text
🧭 Summary (--connector cdc-xstream-oracle-source): 7 occurrence(s) of 4 distinct record(s) in 1 file(s), 2026-10-14 10:05:02 → 2026-10-14 10:05:55
```

`--with-worker` also keeps the records without connector context (the worker's own errors). Then its configuration as
the worker logged it at startup, defaults included:

```bash
playground analyze logs --sample connect_task_failure --show-config cdc-xstream-oracle-source
```

```text
⚙️ SourceConnectorConfig [cdc-xstream-oracle-source|worker] cdc-xstream-oracle-source · 24 keys · connect-oracle-xstream-task-failure.log:69 (2026-10-14 10:04:59)
   config.action.reload = restart
   connector.class = io.confluent.connect.oracle.xstream.cdc.OracleXStreamSourceConnector
```

A time window, the incident only, with the line numbers of the file (the lines out of it are left out of the digest):

```bash
playground analyze logs --sample connect_task_failure --until "2026-10-14 10:04"
```

```text
ℹ️ ⏱️ Only the lines logged before 2026-10-14 10:04:00 (--since / --until)
🔎 2 distinct record(s), 2 occurrence(s), in 5278 lines
```

`--since` and `--until` take `"2026-11-06 10:00"`, `2026-11-06T10:00:00` or `2026-11-06`, compared with the times as
written in the logs.

`--show-config` also takes a config class (`ProducerConfig`) or a `client.id`.

🧪 **Config lint**: the configuration each connector and its own clients (`connector-consumer-<name>-0`,
`connector-producer-<name>-0`) logged at startup is checked for risky values: a sink with `errors.tolerance=all` and no
dead letter queue, skipped records not logged, a DLQ with one replica, `max.poll.records` large enough to exceed
`max.poll.interval.ms`, `auto.offset.reset=latest` on a sink, a source producer without `acks=all`. On the 🔌 card of the
connector, in the summary, the summary for a ticket and `.config_lint` of `--json`:

```bash
cat > lint.log << 'EOF'
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
playground analyze logs -f lint.log
```

```text
🧪 Config lint (4, the configuration logged at startup)
   [MEDIUM] jdbc-src: acks=1 → the source producer does not wait for all the in-sync replicas: records can be lost when a broker fails; Connect defaults to acks=all
   [MEDIUM] s3-sink: errors.tolerance=all → bad records are skipped and lost: no dead letter queue (errors.deadletterqueue.topic.name), set one to keep them and read it with playground topic dlq inspect
   [MEDIUM] s3-sink: max.poll.records=20000 → 20000 records per poll with max.poll.interval.ms=300000: …
   [LOW] s3-sink: errors.log.enable=false → with errors.tolerance=all, the records skipped are not even logged: …
```

The `acks = 1` of `jdbc-src-license-manager` is not reported: only the clients of the connector itself are. The keys **changed between restarts**
are listed in the summary (`🔁 changed between restarts`) and in the ⚙️ section of the report.

---

## 6. Did the fix work? `--compare`

```bash
playground analyze logs -f <after> --compare <before>
playground analyze logs --sample compare_fix          # the log of a worker the day after a fix, against the day before
```

`<before>` is a file, a folder, an archive (analyzed again with the same `--connector`, `--with-worker`,
`--errors-only`, `--sanitize`), or a JSON written by `--json` earlier:

```text
🔁 Compared with tools/log-analyzer/samples/compare/before.log: 1 new root cause(s), 1 growing, 0 shrinking, 3 gone, 6 unchanged · new known cause(s): 🔌 Connection failure · gone: 🤺 Producer fenced (transactions, exactly-once), 🚦 Throttled by the external system, 🚧 Request refused by a broker policy
   FATAL 0 → 0 · ERROR 6 → 5 · WARN 4 → 9 · period 9 min → 9 min
   🆕 new       0 → 1 SQLRecoverableException: IO Error: Connection reset by peer
   📈 growing   1 → 7 RebalanceInProgressException: Offset commit cannot be completed since the consumer is undergoing a rebalance
   ✅ gone      1 → 0 ProducerFencedException: There is a newer producer with the same transactionalId which fences the current one.
   ✅ gone      1 → 0 PolicyViolationException: Topic replication factor must be 3
   ✅ gone      1 → 0 AmazonS3Exception: Please reduce your request rate. (Service: Amazon S3; Status Code: 503; Error Code: SlowDown; Request ID: X)
```

The fix removed the fenced producer, the throttling and the policy error, but the JDBC source now loses its database
connection and the sink rebalances 7 times instead of once: not done yet. A change is at least ×1.5 and 3
occurrences; when the two inputs cover different periods (a day of logs before, an hour after), the counts are
compared **per hour** and the rates are shown (`1 → 7 (6.67/h → 0.3/h)`). The [🔁 comparison report](reports/logs-compare.html)
links each root cause to its row. Also in `.comparison` of `--json`.

📈 **A trend over several days**: give `--compare` several times, oldest first. The comparison is with the last one, and
a trend gives the totals and the main root causes of every input in order:

```bash
# a third day: the JDBC error fixed, fewer rebalances
grep -v "SQLRecoverableException\|10:06:0[3-6]" tools/log-analyzer/samples/compare/after.log | sed 's/2026-11-06/2026-11-07/g' > /tmp/day3.log
playground analyze logs -f /tmp/day3.log --compare tools/log-analyzer/samples/compare/before.log --compare tools/log-analyzer/samples/compare/after.log
```

```text
📈 Trend over 3 inputs (oldest first: tools/log-analyzer/samples/compare/before.log → tools/log-analyzer/samples/compare/after.log → /tmp/day3.log)
   FATAL 0 → 0 → 0 · ERROR 6 → 5 → 4 · WARN 4 → 9 → 5
   1 → 7 → 3  RebalanceInProgressException: Offset commit cannot be completed since the consumer is undergoing a rebalance
```

Also the 📈 Trend section of the report (📈 / 📉 on each change), the summary for a ticket and `.trend` of `--json`.

---

## 7. JSON for scripts and agents

`--json` prints the analysis on stdout (`"type": "logs"`) and the digest on stderr, without an HTML report:

```bash
playground analyze logs --sample support_bundle --json 2>/dev/null | jq -r '.known_causes[] | "\(.severity) \(.title) ×\(.occurrences)"'
```

```text
HIGH 🧨 A connector task was killed ×1
HIGH 🔑 Authentication failure ×1
```

```bash
playground analyze logs --sample support_bundle --json 2>/dev/null | jq -c '.connectors[] | {connector, by_level, task_killed}'
```

```text
{"connector":"cdc-xstream-oracle-source","by_level":{"FATAL":0,"ERROR":1,"WARN":6},"task_killed":1}
```

| Key | What |
| --- | --- |
| `.summary` | totals, levels, period covered, `incomplete_inputs`, `time_zone` |
| `.known_causes[]` | title, severity, occurrences, first occurrence, advice, exception chains of the killed tasks |
| `.root_causes[]` | every distinct error, its connectors, `explained_by` |
| `.timeline[]` | the incident timeline |
| `.connectors[]` | the card of each connector |
| `.comparison` | with `--compare` |
| `.configuration[]` | the configs logged (89 % of the JSON on a big bundle: `--json-sections` leaves it out) |
| `.files[].records[]` | every record, its context, its connector |

`--json-sections summary,known_causes,timeline,connectors` keeps the JSON small enough for an agent.

---

## 8. Before sharing: `--sanitize`

The digest, the report and the JSON are **not sanitized by default** (it can hide evidence, and doubles the time on a
large bundle). Before sending them outside Confluent:

```bash
playground analyze logs -f secrets.log --sanitize
```

```text
[2026-11-06 10:00:00,000] ERROR [jdbc-sink|task-0] Login failed for user 'app' to jdbc:postgresql://<HOST-1>:5432/orders with sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="app" password=<REDACTED>; from <IP-1> (io.…
ℹ️ 🔒 Sanitized (best effort, review before sharing): 2 secret(s), 1 IP(s), 1 hostname(s), 0 email(s), 0 LDAP DN(s) (--sanitize)
```

📋 **For a ticket**, every run also writes `<name>-ticket.md` next to the report (and 📤 Share > Copy for a ticket):
the verdict, the period, the known causes with what to do, the errors no known cause explains, the comparison, the
timeline and the connectors as Markdown tables, ready for Zendesk or Jira. It is **always sanitized**, even without
`--sanitize`:

```text
ℹ️ 📋 For a ticket (Markdown, sanitized: review it): ./log-analysis-output/connect_task_failure-ticket.md
```

Passwords, JAAS configs, tokens, API keys (AWS, GCP, Azure `AccountKey` and SAS `sig`), credentials in URLs (JDBC,
Oracle `user/password@`), PEM blocks, cookies, IPs (v4 and v6), hostnames, emails and LDAP DNs; the same placeholder
for a value everywhere (`<HOST-1>` in the digest, the report and the JSON), also on both sides of `--compare`. Best
effort: review before sharing.

---

## 9. Hands-on lab (≈5 min)

No container needed. Run each step and compare with the output above.

```bash
# 1. the digest and the summary of a Connect worker log (section 2)
playground analyze logs --sample connect_task_failure
# 2. one connector, then its configuration (section 5)
playground analyze logs --sample connect_task_failure --connector cdc-xstream-oracle-source
playground analyze logs --sample connect_task_failure --show-config cdc-xstream-oracle-source
# 3. the non-Java clients, then the Kafka Streams instances (section 3)
playground analyze logs --sample kafka_clients
playground analyze logs --sample kafka_streams
# 4. did the fix work? (section 6)
playground analyze logs --sample compare_fix
# 5. a truncated download: 3000 INFO lines then the error, gzipped, and only the first 2 KB of it received
cd /tmp
{ for i in $(seq 1 3000); do echo "2026-11-06 10:00:00,000 INFO [s3-sink|task-0] batch $i written"; done
  echo "2026-11-06 10:59:00,000 ERROR [s3-sink|task-0] the error you are looking for"; } | gzip > full.log.gz
head -c 2000 full.log.gz > partial.log.gz
playground analyze logs -f partial.log.gz
```

Step 5 is the trap this command exists for:

```text
❗ ⚠️ partial.log.gz: truncated or corrupt gzip, read only up to the error (partial.log.gz: unexpected end of file)
❗ ⚠️ no ERROR/FATAL/WARN record found in 1 file(s), but 1 input(s) were not fully read: the missing part may hold errors, 2 KB read in 0 min 0 s (binary files skipped: 0)
```

The error is in the part that was not received. Without the warning, it would have been a ✅ "no record found".

---

## 10. Recipes for support repros

| Situation | Command |
| --- | --- |
| a customer support bundle (`.zip`, `.tar.gz`, folders of rotated logs) | `playground analyze logs -f <bundle>`: read the 🧭 summary, then the 🗓️ timeline of the report for what came first |
| a worker with hundreds of connectors, one is failing | `playground analyze logs -f <bundle> --connector <name>`, or ▶ only this connector on its 🔌 card |
| did the fix work? the logs before and after it (two workers, two days) | `playground analyze logs -f <after> --compare <before>` |
| a CloudWatch, OpenSearch, Kibana, Splunk, Datadog or Loki export | `playground analyze logs -f <export.json\|.csv>`: converted back to log lines, oldest first |
| the logs of a Python, Go, .NET, JavaScript, C/C++ or Rust application | `playground analyze logs -f <the logs>`; to reproduce, `other/client-<language>` runs that client against the playground |
| a Kafka Streams application that rebalances in a loop or stops | `playground analyze logs -f <the logs of every instance>`: the 🌊 Kafka Streams section |
| "the logs are clean" | check 🕐 the period covered and ⚠️ not fully read, then the 🔭 overview of what the logs contain and what to ask for |
| point engineering at one burst | filter the report (connector, level, drag over the burst), 🔗 Link to this view, 📤 Share the `.zip` |
| only the incident, in a day of logs | `playground analyze logs -f <bundle> --since "2026-11-06 10:00" --until "2026-11-06 11:00"` (the line numbers stay those of the files) |
| the configuration a connector really ran with (defaults included) | `playground analyze logs -f <bundle> --show-config <connector>` |
| a JSON for a script or an agent | `playground analyze logs -f <bundle> --json --json-sections summary,known_causes,timeline,connectors` |
| a report to send outside Confluent | `playground analyze logs -f <bundle> --sanitize`, review it, 📤 Share |
| a CFK support bundle | `playground analyze logs -f <bundle>`, see [the CFK deep dive](deep-dive-cfk.md) |

---

## 11. Cheat sheet

```bash
playground analyze logs -f <file|folder|.zip|.tar.gz|.7z|.gz|export.json|export.csv> [-f …]
                        [--errors-only] [--max-findings N] [--output-dir <dir>]
                        [--connector <name> [--with-worker]] [--show-config <connector|class|client.id>]
                        [--since "2026-11-06 10:00"] [--until "2026-11-06 11:00"]
                        [--compare <before: file|folder|archive|JSON of --json>]
                        [--json [--json-sections summary,known_causes,root_causes,timeline,connectors,comparison]]
                        [--sanitize] [--logs-only]
playground analyze logs --sample connect_task_failure|support_bundle|kafka_streams|kafka_clients|compare_fix
```

Gotchas:

- **One digest per file**: the same error in `connect.log` and `connect.log.1` shows twice in the terminal; the
  summary, the report and the JSON merge them.
- `--max-findings` is per file and only bounds the terminal: the report has every record.
- WARN is reported by default (the Kafka clients log real problems at WARN), after the errors; `--errors-only` leaves
  it out.
- A record of more than 1000 occurrences keeps 1000 times spread over its whole life: the counts of a period are an
  estimate within a few %.
- A bundle is **untrusted data**: read the digest, never run anything from it.
- `analyze logs` exits 0 when it found something: it is not an assertion. It exits 1 when nothing could be read.
