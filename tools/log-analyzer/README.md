# log-analyzer

Samples and HTML report of `playground analyze logs`, the ERROR/FATAL digest of log files, folders and bundles. The
digest itself is plain bash (`scripts/cli/src/commands/analyze/logs.sh`, `summarize_log_errors` in
`scripts/cli/src/lib/cli_function.sh`): it de-duplicates records with an occurrence count and collapses stack traces
to their `Caused by:` chain.

`tools/log-analyzer/test_digest_awk.sh gawk mawk "busybox awk"` runs the digest on the samples with each awk and fails
when one of them errors or finds other records (the Tools tests workflow runs it): the digest must stay portable, mawk
(the default awk of Debian / Ubuntu) refuses a function and a parameter of the same name, for example.

The awk programs that read every line (the digest, the `--since` / `--until` window) run through `log_awk`
(`scripts/cli/src/lib/cli_function.sh`): `mawk` when it is installed, else `awk`, or `PLAYGROUND_AWK` when it is set
(the test sets `PLAYGROUND_AWK=awk` to run its awk wrapper). On macOS, mawk 1.3.4 reads 2.5x faster than the awk of the
system, with byte-identical records on 131 customer log files (3 GB: 113 s instead of 280 s); gawk is 2x slower than
the awk of the system there, so it is never picked. On Linux the three are close (200 MB: gawk 3.0 s, mawk 2.6 s).

## Word and Excel documents, screenshots

`office_export.py <document> <output> [<folder for its pictures>]` reads the logs a customer sent in an office document,
standard library only (these files are zips of XML): a Word `.docx` / LibreOffice `.odt` they were pasted in (a paragraph
is a line, a line break a new line, a tab a tab, the non-breaking spaces of Word spaces), an Excel `.xlsx` / `.xlsm` /
LibreOffice `.ods` sheet a log tool exported (the sheet with the most rows: with the columns of an export it goes through
`json_log_export.write_events()`, oldest first, the Excel dates of the cells with a date format as ISO times; else its rows
are the lines, cells joined by a tab). It prints `<format>\t<lines or events>\t<pictures>`, exit `2` without text, `1`
when the document cannot be read. `analyze logs` converts every such file of the input (`analyze_logs_office`), and walks
the pictures of a document (`word/media/…`, `xl/media/…`) so that `bundle_triage.py` lists them. The files no analyzer
reads are listed in 🧰 Other files of the input instead of being counted as "binary files skipped": 🖼️ screenshots and
pictures (`open` them; transcribe the lines to a `.log`), 📄 PDF (`pdftotext -layout`), `.doc` / `.xls` / `.ppt` / `.pptx`
(save as `.docx` / `.xlsx`). No OCR: tried with the Vision framework of macOS, it reads monospace log lines with errors
that matter (`org.apache` read `orq.apache`, `json` read `ison`, a highlighted or wrapped line split in two).

## Lines logged twice, Grafana / Loki text exports, newest-first files

The digest collapses a line identical to the line before it when it has a timestamp to the millisecond (two appenders
writing the same file: every count and event was doubled), and a multi-line record (a stack trace) identical to the record
before it, by pairs (a WARN logged 4 times in the same millisecond through two appenders is 2 events). The count is the
8th field of `@@PGFILE@@` (`.duplicated_lines` of `--json` and ⚠️ in the summary from 10 % of the lines of a file). A
Grafana / Loki text export (Explore, Download as txt) has a header (`Common labels: {…"level":"ERROR"…}`, not a record)
and an `<epoch ms or ns>\t<UTC time>Z\t` prefix before each line (looked for in the first 20 lines), removed. A file whose
times go down from line to line (newest first, 4 times more descents than rises) has `newest_first` in the 9th field of
`@@PGFILE@@`: first / last seen (lines and times), the order of the records and their times are put back in the order of
time (`.newest_first_files`, ⚠️ in the summary). The text and the context of a record stay the ones of the first
occurrence read (the newest one). A UUID in a message (the id of an event) is masked in the key of a record.

## JSON and CSV exports of log events

`json_log_export.py <input> <output>` turns an export of log events back into plain log lines, oldest first, before
the digest reads them: JSON (CloudWatch Logs Insights, CloudWatch events, Elasticsearch / OpenSearch hits, structured
JSON logs) and CSV with a header row (`.csv`, `.csv.gz`: Kibana / OpenSearch Dashboards Discover, Splunk, Datadog,
Grafana). In a CSV, each row is an event; a cell holding a JSON object (the `log` column with the ECS / logback JSON
line of the container) is parsed and its fields win over the columns, `-` is an empty cell, and the Kibana time
`Oct 14, 2026 @ 19:13:28.977` becomes ISO 8601. Exit `2` when the file is not an export of log events: `analyze logs`
then reads it as it is.

JSON lines are streamed (one event at a time, the order fixed afterwards from the offsets of the events), whatever
the extension: `analyze logs` sends a `.log` / `.txt` whose first character is `{` here. A message without its own
time at its start gets the time of the event (`iso_ts()`: epoch seconds / ms / ns become ISO 8601), and the next lines
of a multi-line message are indented, except exception lines and `Caused by:`.

Also: the Loki query API (`data.result[].values`, streams merged in time order with their labels), Elasticsearch /
OpenSearch hits with `fields` instead of `_source`, Splunk `_time` (its newest-first CSV is reversed), numeric levels
(pino / bunyan `"level":50` is ERROR, syslog / GELF `3` is ERROR), epoch seconds written as a string (`"1697310809.5"`),
and the `stack_trace` of an event without level. A message is taken as an already formatted log line only when it has
a level word **and** a time near its start (`"Task failed: WARN threshold"` of an ERROR event keeps its level, logger
and stack trace). A CSV cell holding JSON is merged only when it is a log line (it has a message), and times with an
offset are compared in UTC to detect a newest-first export. Tests: `python3 -I tools/log-analyzer/test_log_analyzer.py`, run with `tools/report-common/test_sanitizer.py` by the Tools tests workflow (`.github/workflows/tools-tests.yml`) on the pull requests that change `tools/log-analyzer/`, `tools/report-common/`, `tools/streams-analyzer/` or `cfk-analysis/`: once with Python 3.12, once in a `python:3.8-slim` container (3.8 is the oldest supported version) after `compileall` of the four folders, so that a construct of a newer Python (a 3.12 f-string with nested quotes) fails the PR instead of every run on Ubuntu 20.04, UBI 9 or the `/usr/bin/python3` of macOS.

## Without Docker, without the playground

`analyze logs` (and the other offline analyzers: `gc-logs`, `thread-dump`, `oracle-xstream-report`, plus `find-command`,
`find-example`) skip the container engine check of the CLI (`filter_docker_running`), and the CLI has no global `docker`
dependency anymore. It needs bash 4.2+, python3 3.8+ (standard library), the `jq` binary (checked with `type -P`: the `jq`
function of the playground runs it in a container), awk, gzip and tar. A `.zip` without `unzip` is extracted with
`python3 -m zipfile`. Without a container engine, cfk-analysis runs with the local python3 when PyYAML is installed
(`cfk_analysis_local`, `CFK_ANALYSIS_LOCAL=1` forces it), else a CFK bundle has no ☸️ sections (a warning, not a failure),
its pod logs are read. A shallow sparse clone of `scripts`, `tools` and `cfk-analysis` (about 33 MB) is enough: see
"Without the playground" in the deep dive.

With nothing installed but Docker: the `ghcr.io/vdesabou/kdp-analyze-logs` image (`tools/analyze-logs-image`), the same
code. Inside it, `PLAYGROUND_HOST_PATH_MAP=/data=<KDP_HOST_DIR>` maps the folder mounted in `/data` to the folder of the
host: `shown_path` (CLI) for the paths printed, `host_path` of `tools/report-common/log_viewer.py` for the ✏️ links (none
when the host folder is not known, an editor cannot open a path of the container).

## Digests in parallel

`analyze logs` runs the digest of each file in the background, `PLAYGROUND_LOG_PARALLELISM` at a time (4 by default; 1: one
at a time, with the progress bar of a large file), each into its own part files in `$tmp_dir/digests/<n>.*` (output,
exit code, records, gzip errors); `collect_digests` merges them in the order of the input, so the records file, the
counters, the warnings and the terminal output are the same as one at a time (checked on the 4 samples). 40 files of 9 MB:
31 s one at a time, 14 s with 4.

## Progress of large inputs

`progress.py` shows the progress of a large input: `cat` copies stdin to the digest with a bar on stderr (terminal
only, 20 MB or more), `page` writes the 🔄 progress page opened in the browser at the path of the report (the stylesheet and header of
`report_html.py`: a bar for the file being read, as in the terminal, one for the whole input, where an archive counts for its
content once extracted, and tiles; reloaded every 2 s; `log_report.py` writes the report next to it then renames it), `size` and `human` give the size of the
input. The page and the overall progress come from `PG_PROGRESS_*` variables exported by `analyze logs`; the
`Progress` class is also used by `json_log_export.py` while it converts a large file. While the digests run in the background (4 at a
time, no bar of their own), `progress_digests` of `analyze logs` writes the page as they end: the files digested out of
those queued, and the whole input without the files queued but not digested yet. The ⏱️ Elapsed tile ticks from
`PG_PROGRESS_STARTED` as soon as the page loads (not the time of the last step written).

## Overview of logs without findings

`log_overview.py --records <records> --sources <sources> [--exports <exports>] [--json]` runs when no file has a
finding: lines, period covered (the `@@PGFILE@@` timestamps of the digest) and records by level of each file, the most
frequent messages (masked: numbers, hex ids, UUIDs) and loggers, and hints (period shorter than 10 min, only
INFO/DEBUG records, an export of a log console cut at its size limit). `analyze logs` prints it, adds it to the HTML
report (🔭 Overview section) and to `--json` (`.overview`).

The levels of the overview also read logfmt `level=error`, JSON `"level":"error"`, zap / logrus after the time, the
.NET console logger (`fail:`) and klog (`E1014 10:00:05`); a line without level that starts with its own time is a record
of its own, not the next line of the previous one.

## Inputs not fully read

`analyze logs` writes `label<tab>reason` to `$tmp_dir/incomplete` for each input it could not read completely: a `.gz`
that `gzip -dc` stops on (`unexpected end of file`: a partial download, read up to the error), an archive that `unzip`
/ `tar` / 7-Zip do not fully extract, a digest that fails. They are listed at the end of the terminal output, in a ⚠️
**Not fully read** block below the verdict of the HTML report (`log_report.py --incomplete`) and in
`.summary.incomplete_inputs` of `--json` (`[]` when everything was read). With no finding, the verdict is ⚠️ instead of
✅, and the exit code is `1` when nothing could be read at all. The digest (`summarize_log_errors`) runs its awk with
`LC_ALL=C`: in a UTF-8 locale, the awk of macOS stops on the first byte that is not UTF-8 (`awk: towc: multibyte
conversion failure`) and every record of the file was lost; its lines are cut without leaving half a UTF-8 character.

## Files that are not logs, REST API outputs, CFK bundles made by hand

- **Not logs** (`log_report.py --not-logs`): after the digests, `bundle_triage.py --gc-logs <sources>` lists the GC logs
  and `log_overview.py --unleveled --sources <sources>` the files without any line with a log level in their first 4 MB
  (log4j / logback, logfmt, JSON, klog, JVM unified logging, librdkafka `%3|…`): captures of host commands, `kubectl get`
  tables. `analyze logs` writes them to `$tmp_dir/not-logs` (`label<tab>gc|unleveled`); a file with records is a log all
  the same. They are still digested (the GC pauses and the JDK of a GC log join the timeline and the tiles), but their
  dates are left out of the 🕐 period covered and of 🕰️ log coverage (`.summary.not_logs` of `--json`), and an input made
  only of them gets `🔎 No Kafka / Connect log in the input: …` (`.summary.no_kafka_log`) instead of a ✅ and a period. The files that hold the thread dumps analyzed in 🧵 are named as such (`mark_thread_dump_files()`: reason `thread_dump`, "N file(s) of thread dumps (🧵 below)"), not as files without a log level.
- **Kafka Connect REST API outputs** (`rest_dumps.py <file> <folder>`), found by content whatever the extension (the
  whole file is JSON, or JSON documents start lines of a terminal capture): each FAILED connector or task of `GET
  /connectors/<name>/status` or `/connectors?expand=status` becomes an ERROR record with its `[<connector>|task-<id>]`
  context, the worker and its `trace` as the stack trace (no time), digested instead of the file; the other documents
  (`GET /connector-plugins`, connector configs) go to `append_config_file`. A plugin list may have entries without a
  version (`?connectorsOnly=false`); a class listed twice is a 🧩 finding of `config_lint()` (`shadowed_plugins()`):
  HIGH when one has no version (an old jar on the plugin path may shadow the one of the worker), MEDIUM for two versions.
- **CFK bundles made by hand** (`is_cfk_bundle`): a flat collection of `kubectl` outputs needs a
  `confluent-operator-*.log`, two YAMLs of `platform.confluent.io` custom resources, or one with a pod `*.log`; every file
  of it but the YAMLs is digested (a pod log saved as `.txt`). One CR next to a `.txt` log is read as plain files.
- **Verdict**: no record in the logs but issues of a CFK bundle, or a critical / high finding of the input (a shadowed
  plugin): `🔎 No … record in the N file(s) of the log digest, but …`, never a ✅.

## Other files of the input (🧰 bundle triage)

`analyze logs` writes `label<tab>path` of every file it walks (archives extracted) to `$tmp_dir/walked`.
`bundle_triage.py --walked <file>` recognizes, by content (magic bytes, the first 64 KB, the whole file for a thread
dump) or by name, the files that another analyzer of the playground reads better than the digest: GC logs (unified
`[gc` tags, legacy `[GC (`, `[Full GC`; a file named `*gc*` or 5 GC lines in its head), thread dumps (`Full thread
dump` and `java.lang.Thread.State:`, anywhere in a stdout log up to 2 GB, the first MB of a `.gz`), heap dumps
(`JAVA PROFILE 1.0`, `.hprof`), flight recordings (`FLR\0`, `.jfr`), network captures (pcap / pcapng magic, `.pcap`,
`.pcapng`, `.cap`) and Oracle XStream diagnostics reports (`orclcdc` in an `.html`). It prints JSON: `files[]` (label,
path, kind, bytes, kept) and `commands[]`, one per kind and folder for `gc-logs`, `thread-dump` and
`oracle-xstream-report` (they read several files), one per file for the others. With `--keep-dir`, a file extracted to
`--tmp-dir` is kept there as `<archive name>/<path in the archive>`: hard-linked or copied when the report links to it
(`--sources`), moved otherwise, so the commands still work after the tmp dir is deleted. `analyze logs` keeps them in
`<stem>-other-files/` next to the report; not with `--json` (the command then says to extract the archive first).
`log_report.py --other-files <json>` adds the 🧰 section to the summary, the HTML report and `.other_files` of `--json`.
Each file also has `read_path`, where it is in this run (the tmp dir is still there when `log_report.py` runs, also with
`--json`): the inline analyzers below read it when no copy is kept.

### 🧵 🔬 JVM dumps analyzed in the report (`jvm_dumps.py`)

`log_report.py` analyzes the `thread_dump` commands of the triage right away, in its process, with
`tools/thread-analyzer/thread_dump_analyzer.py` (imported: `parse_file`, `analyze`, `html_report`; files over 512 MB are
left to the command): `.thread_dumps` (one group per command and per JVM: dumps, findings, CPU between the dumps, deadlocks, stuck
threads, lock stalls, Connect task threads; the dumps of 2 JVMs in one folder are 2 groups, each one with its files, its
command, `jvm_index` / `jvm_count` and `JVM 2 of 2: <files>` after the JVM version, and its own thread report
`<stem>-thread-dumps-<n>.html`), the 🧵 🔬 **JVM dumps of the input** card right after the verdict, the worst finding in
the verdict, a `lifecycle` event per dump on the 🗓️ timeline (the time the JVM printed, without time zone), and the full
thread report `<stem>-thread-dumps.html` next to the report (in the 📤 `.zip`). The heap dumps are only listed
(`.heap_dumps`, with their `playground analyze heap-dump` command, in the same card and the verdict): MAT needs Docker
and about as much memory as the dump. The `kdp-analyze-logs` image copies `tools/thread-analyzer`.

### 🗺️ Cluster layout (`cluster_layout.py`)

The triage recognizes, by content, the output of `kafka-topics --describe` (`Topic: … Partition: … Leader: … Replicas:`)
and of `kafka-log-dirs --describe` (the JSON with `"brokers"` and `"logDirs"`): kinds `topic_describe` and `log_dirs`,
`inline` (no command, not in 🧰). `cluster_layout.py` reads them: replicas, leaders, preferred leaders per broker,
partitions led by a non-preferred replica (above `leader.imbalance.per.broker.percentage`, 10%), leader and partition
skew (25% above the average and 5 more), offline / under-replicated / under `min.insync.replicas` partitions (from
`Configs:`), topics with replication factor 1, a broker in no ISR; the disk per broker and log dir, a log dir with an
`error`, the disk skew (50% above the average and 1 GB more), biggest partitions and topics, `isFuture` replicas.
`.cluster_layout` of `--json`, 🗺️ in the summary, the report and the summary for a ticket. Alone:
`python3 -I cluster_layout.py topics.txt log-dirs.txt`.

### 🐢 Broker signals

The digest (`summarize_log_errors`) notes INFO / WARN lines of a broker under pressure as `@@PGEVT@@` events, 300 per kind
and file, keyed by broker: `isr_shrink` / `isr_expand` (`[Partition orders-0 broker=1] Shrinking ISR from 1,2,3 to
1,3`), `replica_fetch_error` (`Error sending fetch request`, `Error in response for fetch request`: the leader it fetches
from), `request_timeout` (`Disconnecting from node 2 due to request timeout`: the broker that did not answer),
`log_cleaner` (`kafka-log-cleaner-thread-0]: Error due to`, `uncleanable`), `quota_throttle` (librdkafka `|THROTTLE|`,
`ThrottlingQuotaExceeded`), `response_dropped` (`no open connection, connection id`), `auth_failure` (`[SocketServer
listenerType=BROKER, nodeId=1] Failed authentication with /10.0.0.1 (channelId=…) (errorMessage=…)`, `Failed
re-authentication with`, INFO: handled before the other matches of a line, a storm is millions of lines; the exact count
per broker, client IP and error message in `@@PGEVTN@@ auth_failure_by` lines, 500 per file, the reasons of its rows).
`log_report.py` counts them in
`.lifecycle` (`BROKER_KINDS`, a line without broker id: `broker (<file>)`), with the partitions or peers they happen to
most as reason and a 🌀 storm as the rebalances, prints them in their own 🐢 block, groups them in bursts on the
timeline (`broker_bursts`: less than 5 min apart, from 1 ISR shrink or log cleaner failure, 3 of the others, 20 per kind),
and asks for the JMX metrics of the brokers in 📥. ISR expands without a single ISR shrink are replicas being added (a
replication factor increase, a reassignment, a Self-Balancing move) that join the ISR once caught up: the 🐢 block says so
instead of only "a broker that falls behind" (kept when there are shrinks, fetch errors or request timeouts).

### 📈 INFO messages repeating abnormally

The incidents that log no ERROR at all: an HDFS sink logging `Starting commit and rotation for topic partition <p> with
start offsets {} and end offsets {}` every 7 s and never `Committed`, a broker logging `Failed re-authentication with /<ip>`
hundreds of times a minute. Each needed a hand-written signal (🔂, 🚷); this detector finds the next one without code.
The digest (`it_add()` of `summarize_log_errors`) turns every INFO line with a time into a template: the message without
its `[connector|task-0]` context (kept apart, so a template is per connector), the first word of a leading `[Consumer
clientId=…, groupId=…]` / `[SocketServer listenerType=BROKER, nodeId=1]` kept, quoted values, bracketed lists, `{…}` (an
empty `{}` is kept: it is the anomaly of the HDFS sink), numbers, hex ids that start with a digit, UUIDs and `ip:port`
masked, 160 characters at most. Each template is counted with its first / last time (to the minute) and per minute;
3000 templates and 200000 template-minute cells at most (then the lines of a new template are only counted as `over`).
Cheap: the masking only runs when the quick key of a line (its first 160 characters without the digits) is new, and the
failed authentications of a broker reuse the key of their own fast path. The digest alone takes 10 to 20 % longer (mawk,
a Connect log of 245k lines, 76k of them INFO: 0.55 → 0.63 s; a broker log of 750k lines of failed authentications:
1.52 → 1.71 s), the whole `analyze logs` of that Connect log less than 1 % (5.06 → 5.10 s). Records:
`@@PGINFON@@ <INFO lines> <templates> <over>`, `@@PGINFOC@@ <connector> <INFO lines>` per connector context, then the 25
most frequent templates and the 15 with the busiest minute among the others: `@@PGINFO@@ <count> <first> <last> <busiest
minute> <connector> <template> <line> <example line>` and `@@PGINFOB@@ <minute>=<count> …`.
`info_anomalies()` of `log_report.py` merges the rotated files of a worker and flags a template that is
**steady** (`INFO_STEADY_*`: 30 min or more, at least one every 10 s on average, in 80 % of the minutes of its period, and
25 % of the INFO lines of its connector, or of the lines without connector context of its file) or a **burst**
(`INFO_BURST_*`: a minute with 100 or more and 10 times the median minute of the period, the minutes without any counted
as 0; not within 2 min of a start, stop or rebalance of the file, whose startup logs hundreds of plugin and config lines).
`INFO_CHATTER` leaves out what is normal by nature (offset commits, a sink that commits its files, the poll of a JDBC
source, the progress of a connector, `RestServer` access lines, heartbeats, metrics, fetch sessions, log retention of a
broker) unless it runs at 5 per second or more; `INFO_COVERED` moves what a 🔄 / 🐢 signal already reports (empty
rotations, failed authentications, rebalances, ISR changes…) to `.info_anomalies.covered`. LOW, MEDIUM at 1 per second
or more (steady) or 100 times the median (burst); never a known cause, never in the verdict: the 📈 block of the terminal
(5), the 📈 card of the HTML report (after 🔄), one line of the summary for a ticket and `.info_anomalies` of `--json`
(`rows`, `covered`, `info_lines`; the templates of each file are left out of `.files`).

## Not enough replicas (🧬)

`not_enough_replicas_summary()` (in `match_hints()`, `.known_causes[].not_enough_replicas` of `--json`) reads the
`NotEnoughReplicasException: The size of the current ISR Set(<ids>) is insufficient to satisfy the min.isr requirement of
<n> for partition <p>` records: per partition the occurrences, the window (first → last) and its duration, the ISR and
min.isr, most refused first (a record also stands for the partitions whose names differ only by digits), and how many
partitions had a single replica in sync while min.isr asked for 2 or more. `not_enough_replicas_details()` writes them
under the known cause, in the terminal, the HTML report and the summary for a ticket: the impact table of an RCA, and the
single in-sync replica diagnosis: the other replicas fell out of sync, or the topic has fewer replicas than
`min.insync.replicas` (RF=1 with `min.insync.replicas=2` works, the minimum being capped at the number of replicas,
KAFKA-15583, until a replica is added: every `acks=all` write is then refused until the new replica has caught up).

## Comparison with another input

`--compare <before>` (the logs before a fix, another worker, the day before) runs `analyze logs` again on `<before>` with
`--json --logs-only` and the same `--connector`, `--with-worker`, `--errors-only`, `--sanitize` (and the same sanitizer
state, `PG_SANITIZE_STATE`: a value gets the same placeholder on both sides), or takes `<before>` as it is when it is a
JSON of `--json`. `log_report.py --compare <json> --compare-label <before>` then compares (`compare_reports()`): the root
causes (by label), the known causes (by title) and the connectors are new, gone, growing or shrinking (×`COMPARE_RATIO`
= 1.5 and at least `COMPARE_MIN_DELTA` = 3 occurrences), per hour when the two periods differ by more than 10 % (the
rates are shown), with the totals by level. In the 🔁 Comparison section of the HTML report (after the tiles, the root
causes linked to their row), the terminal summary (also when the input has no finding left: everything gone) and
`.comparison` of `--json`.

`--compare` can be given several times, oldest first: `log_report.py` gets one `--compare` / `--compare-label` per input,
compares with the last one and builds a `trend()`: the totals by level and the main root causes (`TREND_ROWS`) of every
input then this one, per hour when the periods differ (📈 Trend section, terminal summary, summary for a ticket, `.trend`).

## Connectors

`connector_health()` (in `analyze()`, `.connectors` of `--json`) builds one card per connector of the logs (the
`[connector|task-0]` context of the lines), most errors first: its occurrences by level, first and last time, the task
kills (records of the 🧨 known cause), the known causes of its records, its configuration dumps, the clients it owns
(`connector-producer-<name>-0`…) and the keys changed between restarts. The HTML report shows them in 🔌 **Connectors**
(▶ only this connector sets the connector filter and keeps its card only, ⤺ goes back to all, the search filters the cards, the first `CONN_CARDS_SHOWN` = 30 then "show the other N connectors"), the terminal summary one line per connector.
Each card has the icon of the examples of its class on the website (`tools/report-common/connector_icons.py`: class → icon
and, for the classes shared by several databases like `JdbcSinkConnector`, the scheme of the `connection.url` of its
configuration dump → icon, in the committed `connector_icons.json`, linked from GitHub as `docs/content.md` does, 🔌 when
unknown or offline). Run `python3 -I tools/report-common/connector_icons.py` again when an example or an icon is added.

The class of a connector without "Instantiated connector" line nor config dump is inferred from the loggers of the lines
of its tasks (`plugin_logger` events of `summarize_log_errors`): the digest looks for one in the first 20000 lines of the
connector that end with a logger (a broker or DNS outage logs thousands of `NetworkClient` lines in its context first),
then gives up after 500 lines without a new one. A logger that is a connector class of `PLUGIN_PACKAGES` itself
(`Initial connection attempt with the database. (io.confluent.connect.jdbc.JdbcSourceConnector:94)`) gives that class
directly: its package, `io.confluent.connect.jdbc`, is shared by the source and the sink.

## Host names not resolved (🌐)

`dns_summary()` (in `match_hints()`, `.known_causes[].dns` of `--json`) tells a DNS outage from a wrong name: the window
of the records and whether they stopped `DNS_ENDED_AFTER_S` (5 minutes) before the end of their file, the hosts named in
them (without count: a record also stands for the names that differ only by digits), the Java lookups that failed in the
resolver of the OS (`UnknownHostException: <host>: Name or service not known`) vs the failures served from the negative
cache of the JVM (`UnknownHostException: <host>` alone, thrown by `InetAddress$CachedAddresses`), and the Java clients
that could not be created (`No resolvable bootstrap urls given in bootstrap.servers`). `dns_details()` writes them under
the known cause, in the terminal, the HTML report and the summary for a ticket. The DNS records of a component that
starts, like its connection failures, go to the one 🌅 LOW known cause.

## Versions

The digest notes two INFO lines it does not keep otherwise, as `@@PGEVT@@` events of the records file: `Instantiated
connector|task <name> with version <v> of type <class>` (the version of each connector, the class of the connector kept
over the one of its task) and `Kafka version: <v>` (AppInfoParser). The 🔌 card of a connector shows its version (`1.5.0
→ 1.6.0` after an upgrade during the logs) with a 📋 button that copies `playground connector-plugin changelog
--connector-plugin <class> --from <version>` (what changed since: is it fixed in a newer version?), also in the terminal
summary for a connector with errors; the Kafka version is a 🏷️ tile, a line of the summary, `.summary.kafka_versions` of
`--json` and a line of the summary for a ticket.

## Tiles

The tiles at the top of the report (`html_report()`) link to their section (`KPI_LINKS`): 🕐 Period covered to 🕰️ Log
coverage (`#log-coverage`), 🗂️ Files scanned (with the lines and the size read, `--bytes-read`, `.summary.bytes_read`) and 🔥 Files with findings to the files table (`#files-with-findings`), 🧬
Distinct records to 🌳 All root causes (`#all-root-causes`), 🔁 Occurrences (with the count of each level, the level chips
of the filter bar have them too) to 📈 Occurrences over time. A folded section is unfolded; a tile whose section is not in
the report stays a plain tile.

The 🏷️ tile (`version_tile()`) is 🏷️ CP when the version is Confluent Platform: `Kafka version: 8.1.0-ce` / `-ccs` of the
logs, or the image tags of the CRs of a CFK bundle (`cp-server:8.1.0`); 🏷️ Kafka for plain Apache Kafka logs. 🔴 Critical,
🟠 High, 🟡 Medium, 🟢 Low (`findings_severity_tiles()`) count the cards of 🔎 Findings at each severity, the ☸️ CFK ones
included: a click keeps only those cards (the severity chips of the section follow) and goes there, again shows them all.
The tiles of the CFK bundles join the same row (`cfk_kpi_tiles()`: ☸️ CFK issues, clickable, the Kubernetes and CFK
versions). The header (`HEADER_CSS` and `kdp_brand()` of `report_html.py`, shared with the 🔄 progress page) has a 🐳
kafka-docker-playground badge (`KDP_SITE`) and a ❓ How to generate this report link to the deep dive page
(`ANALYZE_LOGS_DOC`), and 🔁 Regenerate (`regenerate_button_html()`, from `--regenerate`): it copies the exact command that generated the report, which `analyze logs` builds from bashly's `command_line_args` with absolute paths for `-f`, `--output-dir` and `--compare` (`--output-dir` added when not given), each argument quoted for a shell. A report is a file opened from disk: it cannot run the command itself, and a link that runs one in a shared report would be a risk. Its gradient follows the verdict of the status pill: red with ERROR/FATAL, amber with WARN only,
green without error. The verdict itself (`verdict_parts()`: a class, a headline, lines) is one sentence in the terminal,
the Markdown and the pill (`verdict_text()`), and in the HTML report a headline with a line per finding under it
(`verdict_box_html()`): 👉 start with (a link to the card of the known cause, `finding_id()`: `verdict_cause()`: known causes are ranked by severity, then the ones with ERROR / FATAL records before the ones seen in WARN records only, then `HINT_ORDER`; the verdict starts with the first one with an ERROR / FATAL record, replaced by a cause further down whose ERROR / FATAL occurrences weigh more, each severity level worth 10 times the next one (`VERDICT_WEIGHT`), more than 10 times more at the same severity; 🪵 log hygiene never; the 📖 Main cause of the story is the same cause), 🤔 Weak verdict (`weak_verdict_text()`: when more than half of the ERROR / FATAL occurrences belong to root causes no known cause explains, a link to 🌳 All root causes), 🔁 restart loop (a link to
the 🔄 section, `#lc-section`), 🧵 / 🔬 / 🗺️ of the JVM dumps and the cluster layout, ☸️ of the CFK bundles. Right under it, 📖 What happened (`story_html()`): logs start → first error → peak (the busiest of
`STORY_BINS` buckets of `error_bins()`) → main known cause → connectors hit → the end of the logs (🔥 still failing with
`STORY_STILL_MIN` errors or more at a tenth of the average rate or more, 📉 fading out below it, a few left under
`STORY_STILL_MIN`, ✅ stopped), each step a link to its section (its text selectable: a drag selects, it does not follow
the link), over an area sparkline (square-root scale): a drag over it makes that range the 🕐 period of the report
(`pgSetPeriod()`), and the current period is shaded on it (`STORY_SCRIPT`). The 🔁 Occurrences tile has the same sparkline (`spark_svg()` of `report_html.py`); the numbers of
the tiles get thousands separators and count up when the page opens (`KPI_JS`, not on the 🔄 progress page).
🔎 Findings opens with 🏆 Top causes (`findings_overview_html()`): a ring with the share of the occurrences of the first
cause, the first `FINDINGS_TOP` ranked like the cards (the most severe first, then the most frequent: a killed task before a
MEDIUM warning that happens more often) with a bar each (their share of all the occurrences, coloured by severity, a link to
their card). A record can match several known causes: the shares do not add up to 100%, so no pie.
🔌 Connectors opens with 🟥 Every connector at a glance (`connectors_heatmap_html()`, 6 connectors or more): a cell per
connector grouped by plugin class (the group with the most errors first), coloured by its ERROR/FATAL on a log scale
(`heat_color()`), amber with warnings only, green without, a dot for a killed task; hover for its name and counts, a click
sets the connector filter (again: back to all), the cell of the connector picked is ringed.
Polish shared by every section (`KPI_LINKS`, `SECTION_TOGGLE`): rounder cards with a hairline border and a shadow that
lifts on hover, a gradient accent under each title, the content of a section fading in when it is unfolded
(`sec-opening`), the count of a section title (🔌 Connectors (485)) as a badge in its quick link and in 🧭 Sections, and a
thin bar at the top of the window showing how far down the report you are (`pg-progress`). Under the verdict, the quick links (`QUICK_LINKS`, filled by `KPI_LINKS` from the titles of
the sections, the record cards of each file left out) open each section the same way.
The 🏷️ CP and 🛠️ CFK tiles show the support of the version (`tools/report-common/support_dates.py`, the
tables of the docs: CP Enterprise Standard then Platinum end of support, CFK Standard end of support; `TILE_CLASS`): ✅
supported (green), ⏳ support ends within 6 months, with the days left, and ⚠️ Standard support ended but Platinum still
running (amber), ⛔ end of support (red, pulsing, and a ⛔ banner right under the verdict, `support_banner_html()`). A `-ccs` version in the logs is Confluent
Community (🏷️ CP Community, `cp_community_status()`: the "Confluent Community Software End of Support" column, no
Standard / Platinum extension). 📡 Clients (`clients_tile()`): the Apache Kafka Java clients ("Kafka version: x.y.z"
without `-ce` / `-ccs`) and librdkafka (`librdkafka_version` events of the digest: `librdkafka v2.3.0 … initialized`,
`confluent-kafka 2.16.1, librdkafka 2.16.0`), against the client support tables of the docs (`JAVA_CLIENT_SUPPORT`,
`LIBRDKAFKA_SUPPORT`). 🛟 Connector versions (`connector_versions_tile()`, and a line on each 🔌 card): the plugin version
of each connector against the minimum supported on the CP release of its worker (the "Kafka version" of the same file),
from the supported-connector-version page of each release (`CONNECTOR_MIN`, 7.9 and 8.0 to 8.4, `CONNECTOR_ROWS` maps
the classes to its rows; copy the table of each new release). Ended versions and unsupported connectors are in the
banner, the terminal summary and the summary for a ticket. The summary and the
summary for a ticket say it too. Update the tables with each release (skill `kdp-bump-cp-version`).
On a wide screen (1400 px or more), the same links are a 🧭 Sections panel on the left (the section on screen
highlighted, ⟨ hides it, ☰ Sections brings it back, remembered in `localStorage` as `pg-side-nav`); a ⬆️ Top button shows
once the page is scrolled down. The jumps use a quick scroll (`pgScrollTo()`, 250 ms) that stops under the sticky filter bar.
The sanitization state (⚠️ Not sanitized, 🔒 Sanitization) is a line under the verdict, not a section, and 📥 Data to
request is the last section.
📤 Share is a button of the header, of the sticky filter bar (next to 🔗 Link to this view) and of the 🧭 Sections panel,
and the S key; all open the same dialog (.zip, summary, summary for a ticket, path, email). The summary for a ticket (`ticket_markdown()`, sanitized) is also offered for Slack and as rich text: `tools/report-common/share_formats.py` converts that Markdown, `md_to_slack()` to text pasted in the Slack message box (`*bold*`, `code`, a bullet per table row, a link as `text (url)`, nothing escaped: the box shows `&lt;` and `<url|text>` as written) and `md_to_html()` to HTML with inline styles, copied as `text/html` (`ClipboardItem`, a selected contenteditable as the fallback) with the Markdown as `text/plain`.

## Sections of a CFK support bundle

The log report of a CFK support bundle is its only report: `cfk_sections_html()` draws a ☸️ card per bundle (the JSON
of `--cluster-events`) right after the verdict, in the styles of the log report: KPI tiles of the issues by severity and
the Kubernetes / CFK versions, 🎯 `--problem`, 📕 the known CFK issues (📚 and 🔒 links), and the environment with the
recent changes. Its issues are cards of 🔎 Findings, one per category at the severity of its worst issue
(`cfk_findings()`, kind `cfk`): the recommendation of the category, then each issue with its file page
(`<bundle>-cfk-files/`). The cards follow the filter bar of the report (`pgCfk()` in `pgApply()`, `cfk_filter_attrs()`):
level (critical FATAL, high ERROR, medium / low WARN), component (`cfk_component()`: `kraftcontroller` is `kafka`),
connector, search and period. A click on a tile of the ☸️ card (🔎 Issues, 🔴 Critical…) or on 🔎 Findings in its title shows only
the ☸️ cards of that bundle at that severity (`cfk-sevout`) and scrolls to the first one; the same tile again shows them all. `verdict()` adds one ☸️ clause (critical and high issues, the categories to
start with) to the verdict of the logs, the worse class of both. Not drawn: the configuration (⚙️), the data to request
(📥) and the log coverage (🕰️), the log report has them.

## Records of a CFK support bundle

`log_report.py --records <file> --records-under <prefix>` (repeatable) prints, one JSON per line and per prefix, the
records of the files whose label starts with `<prefix>/` or `<prefix>:`, keyed by the path after it (labels as written
by `analyze logs`, not shortened), with level, count, lines, times, message, chain, connector and context. `analyze logs`
passes them to the CFK analyzer (`--log-records`), so the issues of the pod logs of a bundle come from the same records
as the log report.

## Data to request (📥)

`data_to_request()` (in `main()`, once `--incomplete` and `--other-files` are read) lists what to ask the customer for
next, each `{what, why, how}`: a complete copy of each input not fully read; a longer window when the logs cover less
than `SHORT_PERIOD_SECONDS`; the logs since the last (re)start of the Connect workers and brokers with errors whose
startup is not in the input (no `START_CONFIGS` dump, no `process_start` event); the plugin version of the connectors
with errors when only that is missing; per `ASK_FOR_CAUSES`, the logs of a component the known causes point at when the
input has none (a regex on their records keeps the broker logs out for a database login failure) and the heap dump, GC
logs, thread dumps or certificates (the chain the server sends, the truststore) that explain a known cause (not when 🧰
found them in the input); and the broker logs when 💥 a burst follows a cluster event without them. When the input points
at Confluent Cloud (`points_at_confluent_cloud()`: a `*.confluent.cloud` host in the records, their context or the
configs, `.summary.confluent_cloud`), no broker log is asked for: an authentication failure asks for the API key, its
service account and the audit log of the organization instead (`CCLOUD_AUTH_ASK`). The Connect workers whose logs cover
less than `SHORT_WORKER_LOG_SECONDS` (`.summary.short_connect_logs`) get a request for a longer window. It never asks for logs
at DEBUG (nor `-Djavax.net.debug`): the support team does not ask customers for them. Shown in the summary, the 📥 section of the HTML report, the summary for a ticket and
`.data_to_request` of `--json`.

## Tasks by worker (🖥️)

`task_workers()` reads the `task_start` events (`Starting task <connector>-<n>`, logged by the worker that runs the task,
whatever the rebalance protocol: the `taskIds` of `got assignment` only list the tasks added with the incremental
cooperative protocol) of each file. A worker is a file without its rotation suffix (`worker_of()`: `connect.log.1`,
`connect.log.2026-11-06-10`, `.gz`), shown by its folder when the folders tell the workers apart. With 2 workers or more:
`tasks[]` (the runs of each task: worker, from, to, starts), `connectors[]` (the workers of its tasks with their starts
and the ERROR / WARN of the connector in that worker's logs) and `only_on` when the errors (`ONLY_ON_MIN_ERRORS` = 3 or
more) all come from one worker while a task of the connector ran on another worker during those errors, its logs covering
that time (`clean_overlap`: an incident that ended before the tasks moved, or the logs of a worker that start later, is not
a difference of the host); `zombies` (`zombie_tasks()`, 🧟; its card in 🔎 Findings is a title, the error count and the failed stop, then one line per fact: errors since the stop, where the task runs, what to do, `zombie_parts()`): a task whose `Graceful stop of task X failed` is on a worker
and that logs ERROR / FATAL records (its `[connector|task-N]` context) on that worker more than `ZOMBIE_AFTER_S` (60 s)
after it, `ZOMBIE_MIN_ERRORS` (3) or more, before any new start of the task there, with its starts on the other workers
since (the instance that replaced it): the worker cancelled and forgot it but its threads still run (a client retrying
its login every 10 s locks an account), only a restart of that worker stops it; a HIGH finding, a line of the summary
and of the summary for a ticket. On a worker whose logs have no `Starting task` line, a restart of the task there would
not show: only a loop of errors (`ZOMBIE_MIN_ERRORS_UNVERIFIED` = 100 or more) is reported, `verified: false`, a MEDIUM
finding; `start` / `end` the period of the swimlanes (first
task start, last line of the logs of the workers). Shown in the summary, the 🖥️ section of the HTML report, the 🔌 card,
the summary for a ticket and `.task_workers` of `--json`.

The 🖥️ section (`task_workers_html()`): a tile per worker (tasks it runs at the end of the logs, tasks ran, starts,
errors and warnings of the connectors whose tasks moved, 🎯 count), one 🎯 block per worker the errors come from (the
advice once, a chip per connector with its errors, the first `TW_TOP_ONLY` shown), then a row per connector (the first
`TW_TOP`, ▾ Show all for the rest): a lane per task (`TW_LANES` at most) with a segment per run coloured by its worker
(`TW_COLORS`, hover for the period and starts), and the errors and warnings of the connector on each worker. It follows
the connector filter (`pgLifecycle()`: the rows and chips of the other connectors are hidden, a picked one shows even
past the first ones).

The names of the workers shown (tiles, legend, errors per worker) are the part that differs (`worker_short_names()`: the
start they share cut at a separator, backed off while what is left is under 4 characters, a long shared end dropped, a
short one such as `.txt` kept, cut in the middle past 28 characters), the full name on hover.

✂️ Overlapping copies: a plain-text log whose first and last shared lines (timestamped, milliseconds included) are also in
a log digested before it (`without_overlap()` of `analyze/logs.sh`, only for logs of the same period) is the same log
downloaded at another time: only its other lines are digested (a copy of the file without the shared block), and
`--same-source` (label, label of the other one, lines shared, lines kept) makes `worker_of()` give both the same worker
(`SAME_SOURCE`, shortened with the labels), with a ✂️ note in 🕰️ Log coverage. Every line in the other one: skipped as a
copy. Before that, two downloads of the last 5000 lines of a connector were two workers, the task moving between them 85
times, and every count nearly doubled.

## Known bugs fixed in a later version (🩹)

`fixed_bugs_found()` matches each entry of `tools/report-common/fixed_bugs.py` (`FIXED_BUGS`: title, plugin, connector
classes, pattern, `fixed_in`, ref, advice) against the records, their text and their raw context lines from their own
first line (`own_context()`: the 2 lines before a record are the end of the previous one). The connectors of the records
that match (or, logged without connector context, the connectors of that plugin) get a verdict from the version of their
🔌 card (`fixed_bugs.verdict()`): `affected` with `upgrade_to`, the first fixed version of its minor line (or of the first
line above it); `fixed` when its line has the fix (a line newer than every fixed line has it); `unknown` without a
version. A connector of another plugin (its class does not match `classes`) is left out. Shown in the summary, the 🩹
section of the HTML report (after the findings), on the 🔌 card, in the summary for a ticket and in `.fixed_bugs` of
`--json`. A new entry: the changelog line (`playground connector-plugin changelog -c <plugin> --grep <ref>`, the first
fixed version of each line) and the pull request of the fix, which gives the exception and the frames to match. A bug
of the Connect runtime (`"runtime": "cp"`, KAFKA-19697) has Confluent Platform versions in `fixed_in` (`playground
cp-changelog --from <x.y.0> --component kafka --grep <PR>`) and gets its verdict from the CP version of the worker that
logged the record (`Kafka version: x.y.z-ce` / `-ccs` of the same file, else the only one of the input), one per
connector and version.

The catalogue (37 entries: Oracle CDC, Oracle XStream CDC, JDBC, S3, HDFS 3, Azure Blob / Data Lake Gen2, IBM MQ,
Salesforce, ServiceNow, BigQuery, Kinesis, SFTP, and the Connect runtime, MirrorMaker 2 and the broker) comes from the
release notes: `playground connector-plugin changelog -c <plugin> --from <old version> --json` and `playground
cp-changelog --from 7.4.0 --component kafka --json`, keeping a note only when it names a symptom visible in the logs (an
exception and its message, a quoted error, an ORA- code) and its fixed versions, and the frame or message checked in the
code of the fix. A regression has `introduced_in` (the first affected version of each line, from the note): a version
before it, or a line older than all of them, gets `fixed` (not this bug). Plugins without a changelog feed (Debezium,
Replicator, Snowflake, Splunk, MongoDB) have no entry.

## Config lint

`config_lint()` checks the last dump of the configuration of each connector (`SinkConnectorConfig`,
`SourceConnectorConfig`, `ConnectorConfig`, a connector config file) and of its own clients (`ConsumerConfig` of
`connector-consumer-<name>-*`, `ProducerConfig` of `connector-producer-<name>-*`, not the other clients of its context
such as a license manager): `errors.tolerance=all` without a DLQ on a sink, skipped records not logged, a DLQ with one
replica, `max.poll.records` ≥ 5000 with `max.poll.interval.ms` ≤ 300000, `auto.offset.reset=latest` on a sink, `acks` other
than `all` on a source producer. 🧪 on the 🔌 card, the terminal summary, the summary for a ticket, `.config_lint` of `--json`.

## Errors right after a change

`link_causes()` (in `incident_timeline()`) marks a first ERROR / FATAL or a known cause that comes within
`CAUSE_WINDOW_SECONDS` (10 min) after a change, the latest one before it, of the same connector when both have one:
a config key changed between two dumps of the same config (`@@PGCFGCHG@@`; on the line of the dump it replaces "connector
(re)configured", several keys add up), or a worker / broker restarted (not its first start in a file). Not a connector
created, not a WARN. `.timeline[].after` of `--json`, 🔗 in the timeline of the report, `🔗 Errors right after a change`
in the terminal summary and the summary for a ticket.

## Restarts and rebalances

The digest also notes the lifecycle of the INFO lines (`@@PGEVT@@` events, 300 per kind and file, and `@@PGEVTN@@` counts over the whole file, `kind, who, count, leaves`: `leaves` the consumer group rejoins due to `consumer pro-actively leaving the group`, a consumer closed on purpose; a group made of those is never a 🌀 storm and comes last, also when none of its events is among the 300 noted, the 100 groups of the short-lived consumers of an Oracle CDC connector):
`Rebalance started` of a worker group, `Request joining group due to: <reason>` of a consumer group, `Starting connector`,
`Starting task` (its task id as detail), `Kafka Connect started` / `worker initialization took`, `Kafka Server started` / `Transition from
STARTING to STARTED`, the stops (`] shutting down (kafka.server`, `to SHUTTING_DOWN`, `Kafka Connect stopping`), the failed
starts of a worker (`process_start_failed`: `ERROR Failed to start Connect`, logged after `worker initialization took` when the
startup gives up, so that line alone is not a successful start), the active
controller changes (`Becoming the active controller` of KRaft, `elected as the controller` of ZooKeeper) and the GC pauses
of 1 s or more of a GC log (`gc_pause`, detail `<ms> <what>`: unified `GC(12) Pause Full (…) … 2512.789ms`, legacy
`[Full GC …, 1.8234560 secs]`, the total before `[Times:`; a GC log decorated with the uptime only has no time, no event). `lifecycle()` counts them per group / connector with the rate per hour of the period covered and
marks a 🌀 storm (`STORM_MIN` = 10 at `STORM_PER_HOUR` = 6 or more, a consumer leaving on purpose excluded): the 🔄 Restarts
and rebalances section, a line on the 🔌 card of a connector, the (re)starts and the first 20 worker group rebalances in
the 🗓️ timeline, the terminal summary, the summary for a ticket and `.lifecycle` of `--json`.
🔂 `sink_empty_rotation`: `Starting commit and rotation for topic partition <p> with start offsets {} and end offsets {}`
of a sink of files (HDFS), per connector, against the `Committed <file> for <partition>` it logs (`sink_commit`, counted
only): `SINK_LIVELOCK_MIN` (10) of them or more and no commit is a **LIVELOCK** row (`livelock` of `.lifecycle`, first
with the storms): the sink keeps rotating without data to commit and never logs Committed, a put() loop that does not
progress.
The 🔄 section draws them over time (a zoomable chart, one series per kind) and each row has a swimlane of its
occurrences on the period of the table (`LC_BINS` = 120 buckets, a tick per bucket with occurrences, darker with more),
from the times noted (`_times` of each row, left out of `--json`). Logs that cover less than an hour (`.lifecycle.hours`) show
the count over that period (`10 in 5 min`) instead of an extrapolated rate per hour; only a 🌀 storm is red.
The 🔄 section follows the connector filter (`pgLifecycle()`): each row carries the connector it belongs to
(`lifecycle_connector()`: the connector or task started, the sink connector of a consumer group, as `data-conn`), the rows of
the other connectors are hidden and the worker group rebalances and process starts, which concern every connector of the
worker, stay.

🔁 A restart loop (`restart_loops()`, `.lifecycle.loops` of `--json`): per worker or broker, its rotated files merged
(`worker_of()`), `RESTART_LOOP_MIN` (3) failed starts or more, or `RESTART_LOOP_MIN` + 1 stops or more at a median interval of
`RESTART_LOOP_EVERY_S` (30 min) or less. The service manager (systemd, Kubernetes) starts the process again and again and it
never runs, which the counts of the table alone do not tell (20 failed starts over a 2-day bundle read 0.4/h). Each loop gets a
red banner at the top of the 🔄 section ("🔁 Restart loop: Kafka Connect (connect.log) failed to start 20 times, … a new attempt
every ~5 min 40 s", with the known cause whose title says *start*), a 🔁 restart loop badge on its failed starts and stops
rows (sorted first), a `🔁 RESTART LOOP` line in the terminal summary and the summary for a ticket, and a sentence in the verdict.
The failed starts are 💥 events of the 🗓️ timeline.


A click on a 🔄 row (`LIFECYCLE_SCRIPT`): the chart (`lc-chart`) is drawn again with the times of that row only (`data-times`, `encode_times()`, in its series `data-series`: `box.setTimes()`), zoomed on its first → last occurrence, and the `tr.lc-occ` row under it opens: the `_occ` of the row, (time, file, line) of the first `LC_OCC_SHOWN` (100) noted, each a link to its line in the page of the file (`write_viewers()` marks these lines, so the page of a big file keeps them). Again, ⤺ every row or Esc: every row; the connector filter hiding the row unpicks it.
## Knowledge-base articles

📚 What to read about a known cause. `LINKS` in `tools/report-common/known_causes.py` only holds its public docs.confluent.io page (`docs`). Its Confluent support knowledge-base articles (for signed-in users) are **not in this public repository**: they come from the private `reproduction-models/_miscellaneous/log-analysis/kb-links.json` (`kb_links()`, `$PLAYGROUND_KB_LINKS_FILE` gives another file), `{"links": {"<known cause title>": [{"kb", "kb_title", "pattern", "fallback", "ccloud"}]}}`. A cause with several articles has a list; an article with a `pattern` (case-insensitive regex) is about one variant of the cause and is shown only when a record of the cause matches it, before the general ones (`MAX_KB_ARTICLES` = 3 at most; a general article marked `fallback` only when none matched; `"ccloud": True` only when the input points at Confluent Cloud, `"ccloud": "records"` only when the records of the cause name a `*.confluent.cloud` host). They are in `--json` (`known_causes[].kb_articles`, and `kb` / `kb_title` for the first one), a `📚` line each in the terminal summary, the What to do column of the summary for a ticket and the finding card of the HTML report. Without the private repository (a fork, CI), the known causes keep their docs pages only. Never build a URL by hand.

📚 The knowledge base by error message: the private `kb_index.json` (same folder, `$PLAYGROUND_KB_INDEX_FILE`) lists the articles that explain one precise log message, each with the signature of that message (a regex, its longest literal run used as a quick filter) and, when the title names a product, a `context` regex the records must match too: patterns taken from the titles, plus the messages quoted in the body of the articles, checked word for word (`"verified": true`). `kb_for_texts()` matches them in the records, the most specific signature first: a root cause no known cause explains gets `kb_articles` (`--json` `root_causes[].kb_articles`, a `📚 KB` line on its 🌳 card, in the terminal and in the summary for a ticket), and a known cause gets them after its curated articles, in the room left. An article of `kb-links.json` keeps its rule there (its variant pattern, the records it must not match) and is never looked up.

The internal runbooks of Confluent support (GTS Confluence pages, support.confluent.io articles restricted to
*Confluent - Internal*: PKIX, SASL investigations, authorization triage, converters, DLQ, consumer group rebalancing…)
are never in this repository: `known_causes.internal_links()` reads them from the private
`reproduction-models/_miscellaneous/log-analysis/runbooks-internal.json` (`PLAYGROUND_LOG_RUNBOOKS_FILE` for another
file), `{"links": {"<known cause title>": [{"title": "...", "url": "https://...", "pattern": "optional regex of a variant"}]}}`, the same idea as the CFK runbooks
(`cfk-analysis/runbooks.py`). They are a `🔒` line after the `📚` one in the terminal summary, a `🔒` link in the finding
card of the HTML report and `known_causes[].internal_links` in `--json`, but never in the summary for a ticket (it can
leave Confluent). Without the private repository (a fork, CI), nothing changes.

```text
   [HIGH] ⌛ Records not delivered in time ×5 in 2 files (first at python-producer.log line 27)
      → the producer gave up on records not acknowledged within message.timeout.ms (librdkafka) / …
      📚 KB: "TimeoutException: expiring records for topic": <the article, from the private kb-links.json>
```

## Summary for a ticket

`ticket_markdown()` writes the verdict, the period, the known causes with what to do, the errors no known cause explains,
the comparison, the timeline and the connectors as Markdown (tables), **always sanitized** with `sanitizer.py` (a
ticket can leave Confluent): `--ticket-out <path>` (`analyze logs` writes `<stem>-ticket.md` next to the report) and 📤
Share > 📋 Copy for a ticket (`<script type='text/plain' id='pg-share-ticket'>`).

## Size of the report

The 🌳 root cause rows link each file to its page without the ✏️ of the editor (the page has it), the style of the ✏️
links is in `BASE_CSS` (once), and the links have no `rel='noopener'` (implied by `target=_blank`): 6,000 distinct records
make an 11.5 MB report instead of 12.9 MB. The page of a file over `MAX_FULL_BYTES` (2 MB) reads it as a stream and keeps
only the windows around the findings (`log_viewer.read_windows`), and the copy of a `.gz` for the editor is
decompressed as a stream: 101 MB of memory instead of 175 MB for a 44 MB log.

## Incident timeline

`incident_timeline()` (in `analyze()`, `.timeline` of `--json`, at most `TIMELINE_LIMIT` = 200 events) merges all the
files in one chronological list: the first occurrence of each root cause (the record's own message, `record_label()`;
not for a root cause whose first record a known cause covers, unless it is where that known cause starts: the known cause
row says it), the first occurrence of each known cause (one row with the error when they are on the same line), the (re)starts of the
components (a `START_CONFIGS` dump logged at startup: `DistributedConfig`, `KafkaConfig`…), the connectors (re)configured
(once per connector and minute) and the config keys changed between restarts (`@@PGCFGCHG@@`). A dump is keyed by its
class, its `[connector|task-0]` context and its `client.id` (else `name`, `converter.type`, `task.class`); a run starts at
a stop line or when the component dumps its own config again (`worker initialization took` and `Kafka Connect started`
come in the middle of a startup, between the clients it creates, and do not start one). At the end of each run
(`cfg_eval`), a variant of a key that no earlier run had is a change only when its closest earlier variant is gone from
the run: two clients with the same `client.id` (the two consumers of the license manager, one at `latest`, one at
`earliest`), the converter of a connector next to the one of the worker, the admin client of another component are new
instances, not changes. A connector config is compared with its previous dump at once (reconfigured without a restart).
⚙️ A broker config changed while it runs (KRaft `DynamicConfigPublisher`: `Updating node 1 with new configuration :
leader.replication.throttled.rate -> 10485760`, `Updating cluster configuration : …`) is a `dynamic_config` event of the
digest, and the topics given throttled replicas (`Updating topic orders with new configuration :
leader.replication.throttled.replicas -> 0:1,0:4`: their partitions are being moved) are `replica_move` events.
`mark_live_configs()` marks the dump logged at most `LIVE_CONFIG_DUMP_S` (3 s) after a `dynamic_config` line of its file
as live: the broker logs its whole `KafkaConfig` again, which is not a start (no 🔄 row) and its changes say `🔧 changed
live, no restart` in the ⚙️ section. `live_config_rows()` writes one timeline row per minute for all brokers (`⚙️ broker
config changed live, no restart on 4 files: leader.replication.throttled.rate 9223372036854775807 → 10485760 · 🐢
replication throttle…`, the keys with their previous value from the dump, else the keys of the line) and
`replica_move_rows()` one per burst of moves less than `REPLICA_MOVE_GAP_S` (5 min) apart (`♻️ replicas moved under a
throttle on 29 topic(s) in 2 min 31 s: …`). Both are changes (🔗 the errors right after). The terminal lists the
changes beyond the first 8 rows of the timeline under `⚙️ changes later in the timeline`.
Only what has a
timestamp. The HTML report shows it in 🗓️ **Incident timeline** right after the findings (30 rows, the others in a
`<details>`, 📄 links to the line), following the filters (`pgTimeline()`: level, component, connector, period, and the search through the record of a first error; the restarts and configurations without connector stay); the terminal summary prints its first 8 events.

Above the table, `pgTimelineChart()` draws the rows shown (so it follows the filters, and includes the rows of the
`<details>`) as an SVG: one lane per component, x proportional to the time, a mark per event whose shape and color give
the kind (● first ERROR / WARN, ◆ known cause, ▲ (re)start, ○ rebalance or process start, ■ connector (re)configured or
config changed). A gap of 2 minutes or more that is a quarter of the span is cut (`⫽ <duration>`, fixed width), so a
burst after a quiet period stays readable. Marks that would touch go above or below. Hover gives the time, the time
since the first and the previous event and the text; click (or Enter) scrolls to the row and flashes it. The caption
gives the span and the biggest gap. `pgTimelineDeltas()` fills the Δ column (time since the previous row shown; bold
when 30 s or more, half of the biggest gap and 15 % of the span).

The timeline also has the infra events (`kind: infra`, ✕ on the chart): the processes stopped and the active controller
changes of the 🔄 lifecycle, and the `GC_PAUSES_SHOWN` = 20 longest GC pauses of 1 s or more. `link_causes()` takes them
as changes for the 🔗 errors that follow, within `INFRA_CAUSE_WINDOW_SECONDS` = 120 s (a config change keeps 10 minutes).
With `--cluster-events <cfk-analysis JSON>` (repeatable, `analyze logs` passes the JSON of each CFK bundle), the
`.timeline` of the bundle joins too, its times read as UTC: a `Pod` entry (terminated, restarted, with its reason) is an
infra event, a custom resource edited or a StatefulSet rolled out a `config_change` (🔗, 10 minutes), both `cluster: true`
(💥 counted after them too). Their location is `☸️ <component>/<kind>/<name>`, without a line. The whole analysis of each bundle is kept too: the
summary for a ticket gets its ☸️ section (`cfk_ticket_lines()`: environment, issues by severity, known CFK issues with
their public links only, critical and high issues) and `data_to_request()` adds its data to request (`☸️ <what>`, its
`command` as how). Its configuration joins `.configuration` (`cfk_configs()`, source `cfk`, before the configs of the
logs so that config lint keeps the logged one): the properties rendered by CFK, the `configOverrides` of each CR, the
Connector CRs (`Connector CR`, attributed to its connector by `is_connector_config()`). `config_drift()` compares each
key of a Connector CR with the last dumps the worker logged for that connector (not its clients): values normalized
(`class ` prefix, `[a, b]` lists, `null`), `[hidden]` / `<REDACTED>` and `${…}` skipped, keys the logs do not have
left out. `.config_drift`, 🔀 in the summary, on the 🔌 card and in the summary for a ticket. In the HTML report, the
configuration of a bundle is one ☸️ block at the top of ⚙️ Configuration, laid out as in the CFK report
(`cfk_configuration_html()`: a heading per component, a block per CR with its rendered properties, `configOverrides`,
`jvm.config` / `log4j.properties` / `plugins.json` and the dumps logged at startup, a block per connector with its CR and
the config logged, the 🔀 keys highlighted), not again as config classes; the filter and the Connector picker apply.
`after_effects()` counts the ERROR / WARN occurrences of every file (their kept timestamps, weighted by their stride) in
the `EFFECT_WINDOW_SECONDS` = 60 s after each infra event and each process (re)start: when they reach `EFFECT_RATIO` = 3
times the average per 60 s of the logs (`EFFECT_MIN` = 5 at least), the event gets `effects` (occurrences, usual rate, the
3 biggest by known cause, else exception, else message): a 💥 line under its row, a 💥 block of the terminal summary
and of the summary for a ticket.

## Times and time zones

`--since` / `--until` (`log_window_filter` of `analyze logs`): the lines out of the window become empty lines before the
digest (the line numbers stay those of the file, for the links to the file pages), a line without its own time follows
the line before it; the times are compared as text, as written in the logs. The window is in the title of the report.

The digest keeps the offset written after a timestamp (`2026-10-13T10:00:05.123+02:00`, `…Z`, `…-0700`, as `+HH:MM`).
`log_report.parse_records()` then normalizes every timestamp to 19 characters (`normalize_times()`, also used by
`log_overview.py`): with one offset in the whole input (or none), it is stripped and the times stay **as written in the
logs**; when the files mix several offsets (UTC broker logs and local time Connect logs), the times with an offset are
**converted to UTC**, else they would be hours apart with a fake gap: `🌐 times in UTC: the files mix the offsets …` in the
summary, `🌐 UTC` on the 🕐 Period covered tile, `.summary.time_zone` (`offsets`, `converted_to_utc`, `without_offset`) in
`--json`. Times are wall clock times encoded as UTC epochs (`epoch()`, `report_html.wall_epoch()`) and shown with the UTC
fields of JavaScript (`stamp()` of `zoom_chart.js`, `pgStamp()`): a report shows the same times in every time zone, and a
DST change of the machine that writes it adds no hole to the 📈 chart.

## HTML report and JSON

With `--sources <label<tab>path<tab>1 when the file stays on disk>` (written by `analyze logs`) and `--html-out`,
`tools/report-common/log_viewer.py` (shared with the CFK report) writes a page per file with findings next to the
report in `<report>-files/`; the file names and line numbers of the report link to them (`#L33`), and a ✏️ opens the
file in the editor of `PLAYGROUND_EDITOR` (`playground config editor`, VS Code by default): the input file itself, or a
copy next to its page for a file extracted from an archive or a `.gz`.

With `PG_LOG_DIGEST_RECORDS_FILE` set, `summarize_log_errors` also appends every distinct record to that file, and
the `@@PGFILE@@` line of each file ends with the **first and the last timestamped line of that file** (any level, not
only the records): that is the period the logs cover, in `.summary.log_first_timestamp` / `.log_last_timestamp` /
`.log_duration_seconds` of `--json`, in the 🕐 **Period covered** tile of the report and in its header. A window
shorter than `SHORT_PERIOD_SECONDS` (10 min) turns the tile orange (`⚠️ short window`) and adds a line to the 🧭
summary: the bundle may not even contain the incident. The Connect workers whose own logs (all their rotated files)
cover less than `SHORT_WORKER_LOG_SECONDS` (2 min) while the input as a whole covers more (a CFK bundle keeps the end of
each pod log, the brokers cover days) are `.summary.short_connect_logs`: a ⚠️ line of the 🧭 summary and of the summary
for a ticket (`short_connect_logs_text()`), and a request for a longer window in 📥. A records file written before that
(no field 5 and 6) falls back to the span of the records.
`log_report.py` reads it and writes the HTML report (`--html-out`) or prints the analysis (`--json`): known causes
(task killed, with one line per distinct exception chain of the killed tasks (an exception without a message,
`WakeupException`, `NullPointerException`: 📍 where it was thrown, `thrown_at()`, its first frame and the first one of its
caller outside the JDK and the Kafka clients, from the context of the record, and 📝 the message of the log line that
reported it), authentication, cloud credentials (an AWS
`SignatureDoesNotMatch` or `(Service: S3, Status Code: 403`), TLS, unknown magic byte,
`OutOfMemoryError`…, each pointing at its earliest occurrence; the list is shared with the CFK analyzer, in
`tools/report-common/known_causes.py`), occurrences over time, 🗂️ the files with findings (a 📁 header per folder, a card
per file with its component, the occurrences with a bar split by level, the levels as pills, also in the title of the card of each
file; `pgFilesTable()` counts them again for the filters), root causes
(deepest exception of each record; a record without exception by its message, `root_causes()` ignoring its numbers, its
`{…}` maps and its `(A|B|C)` lists: one root cause for an Oracle CDC `Failed to commit consumer offset {0=36227957} for
tables 0=DB.T24(A|B|C)` of every task; and, in the key of both, the name of its connector and task, its client ids and
its durations, `mask_names()` and `DURATION_RX` of `mask_ids()`: one root cause for `Graceful stop of task <name>
failed.` of 149 connectors, `[7336us]` / `[19ms]`, the one-shot clients `consumer-<connector>-<task>-<table>-<seq>`; the
connectors are listed with it. `--compare` matches the root causes on that key, not on their label) and every record (with a 📋 Show context block: the raw lines around its first
occurrence, from the `@@PGCTX@@` lines of the records file) and the ⚙️ configuration (the `<Class>Config values:`
dumps of the logs, keys indented with a tab, or with spaces when the log was copied from a ticket, a web console or an
editor that converts tabs, from the `@@PGCFG@@` / `@@PGCFGL@@` blocks, with the keys changed between two dumps of the same
config from the `@@PGCFGCHG@@` lines, and the `.properties` / connector JSON files that `analyze logs` appends), with a
level and connector filter (connector taken from the
`[connector|task-0]` / `[connector|worker]` context of the line, also with a scope like `[connector|task-0|redoLog]`, or `WorkerSinkTask{id=connector-0}`)
every connector name of the report (a `.fi-conn` chip: root causes, records, cards, 🔄 rows) that the Connector filter
lists sets it on click, again goes back to all (`pgMarkConnChips()`, the chips of the connector picked are highlighted),
a period filter (drag over the 📈 occurrences chart, `[from, to)` as its buckets), the Component chips (the component of
each file from the deepest part of its label: the file name `server.log` / `connect.log` first, then its folders, then the
archive; counted in occurrences, like the level pills; the one picked is remembered in `localStorage` and the chart is
drawn again for it on load) and the search box (`pgCompile()`: words that must all be there, `-word` to exclude, `"a phrase"`, `/regex/` and
`-/regex/`, an invalid regex searched as text; the records whose block passes it, `pgMatch` in `pgKeeps()`; the matches
highlighted with the CSS Custom Highlight API, `pgHighlight()`, the page itself untouched; a
finding card that does not contain it gets `.pg-nomatch`, never the `hidden` attribute of the severity chips). The filters are written in the URL of the page (`#pg:lvl=1&comp=connect&conn=s3-sink&q=timeout&t=<from>-<to>`,
`pgStateWrite()` / `pgStateRead()`, the URL wins over the component remembered in `localStorage`; `t` is the period asked,
`lq` the query of 🔎 Search every log line): 🔗 **Link to this view**
copies it, and the link opens the report on the same view. ⚠️ `connect_without_mdc()` reads the Connect files of the sources file again (until their first `[connector|task-0]` context, 200 lines of tasks without one, or 64 MB): 3 lines of tasks or more (`MDC_TASK_LINE_RE`: `Instantiated task`, `Creating task`, `WorkerSinkTask{id=…}`, the connector configs; not `Starting task`, logged by the herder without context) and no context in the file is `.summary.connect_without_mdc`: a note under the verdict, a line of the summary and an item of 📥 Data to request with the log4j fix (`MDC_HOW`). analyze logs passes `--sources` to every run of the report for it (summary, `--json`, HTML). The 🕐 **period picker** and 🔎 **Search every log line** live
in `tools/report-common/log_search.py` (`period_row()` + `PERIOD_SCRIPT`, `write_index()` + `search_html()` +
`SEARCH_SCRIPT`, emitted right after `FILTER_SCRIPT`). Every way of picking a period ends in `pgSetPeriod(from, to)`: it
zooms the occurrences chart on the part of the period the chart holds (`box.range()` of `zoom_chart.js`: `show()` would
shift a period that goes past an end) and sets `pgWindow` to the whole period; `pgPeriod` keeps the period asked and a
`pgperiod` event tells the search. The quick ranges are relative to the end of the logs (`data-lo` / `data-hi` of
`.pg-period`, the first and last timestamped line), the times of the analysis come from `period_picker()` of
`log_report.py`. The search: `write_index()` writes every line of the files of the sources file (`entries_from()`) to
`<report>-files/search/s<n>.js`, about 4 MB of lines each, a `.js` that calls `pgLogShard(name, "<base64 of gzip of
{x: lines, t: time index}>")` (a page opened from `file://` cannot `fetch()` a file next to it, a `<script>` can); the
time index is (line, epoch) pairs where the time changes, delta encoded, the lines without a timestamp of their own
taking the time before (also across shards), offsets converted to UTC like the digest when the files mix them. The
files with findings first, then the smallest, within `PLAYGROUND_LOG_SEARCH_MAX_MB` (200 by default, `0` off); not
written for a sanitized report. In the page the shards are loaded on the first search, inflated with
`DecompressionStream`, kept while they fit in about 260 M characters (least recently used out), scanned with the first
positive term as a global regex then each candidate line tested against the others (a newer search stops an older one
between shards); up to 200,000 matches kept, sorted by time, shown 200 at a time. These
filters drive **everything below the filter bar**
from one index of records written once in the page, `occurrences_json()`: `<script type="application/json"
id="pg-occurrences">` holds `[root cause index, level, connector index, occurrences, epoch seconds, record index, file
index]` per record, the times being the first value then the deltas in base 36 (`encode_times()` / `pgTimes()`). On
each change `FILTER_SCRIPT` counts them again and redraws the 📈 chart (`window.pgChartTimes()` builds its series and
`box.setTimes()` of `zoom_chart.js` draws them, the x axis pinned by `xmin` / `xmax`), the 🔝 top causes bars, the 🌳
root causes rows (`tr.rc-row[data-cause]`), the 🗂️ files rows (`tr.file-row[data-file]`) and the record blocks
(`details[data-rec]`, `.rec-count`). The period comes from the `zoomchange` event of the chart (id
`occurrences-chart`). The 🔎 findings are the exception: their text is never rewritten (it is the diagnosis of the
bundle), each card only gets `▸ N of M occurrence(s) here` in its `.rec-scope` span, or is hidden (`.other-comp`, with
a `🙈 … show them` note) when none of it is in the selection - from the `data-recs` indexes that `findings_html()` writes for an item with `records`. The times of a record of more than 1000 occurrences are sampled by `summarize_log_errors` over its whole life (every
stride-th one, the stride doubling each time 1000 are kept: `@@PGTS@@\tx<stride> t1 t2 …`), and each time kept stands for
`stride` occurrences: the 8th field of a record in `pg-occurrences`, the weights of the chart (`times.weights`, prefix
sums in `zoom_chart.js`) and the counts of a period (`pgInWindow()`). Before, the first 1000 were kept: an error of a
whole day was a burst at its start in the chart, and 0 in any later period. Only the occurrences on a line without a
time stay out of a period; the legend of the root causes says how many there are.
`tools/connector-diagnose/diagnose_report.py` imports it for the
errors section of the `playground connector diagnose` report. `get-ci-result --logs`, `container logs --errors --html`
and `container display-error-all --html` write the same report (`--unit script|container`, `--section` for the last
lines of a failed CI script, `--link` for the issue and the job).

`--html-section <title> <file>` embeds an HTML fragment written by another playground tool after the findings: the 🌊
Kafka Streams view of `tools/streams-analyzer` (state of each instance, timeline, task assignment, Kafka Streams
errors), which `analyze logs` adds when files of the bundle contain Kafka Streams lines (and to `--json` as
`kafka_streams`).

For the terminal of `analyze logs`: `--text-summary` prints the bounded 🧭 summary (time range, period covered, per-connector counts,
known causes with their advice, root causes no known cause explains, configuration inventory and changes),
`--show-config <name>` the configs of a connector / config class / client id, `--connector <name>` (repeatable,
`--with-worker`) keeps only the records and configs of these connectors everywhere, and `--json-sections` picks the
sections of `--json`.

```bash
playground analyze logs --sample support_bundle --output-dir /tmp/log-reports   # support_bundle-log-report.html
playground analyze logs --sample connect_task_failure --json 2>/dev/null | jq '.known_causes[].title'
```

## Samples

Real logs of `connect/connect-cdc-xstream-oracle19-source`, CP 8.3.2, Oracle XStream CDC connector 1.6.0:

| `--sample` | File | Content |
| --- | --- | --- |
| `connect_task_failure` | `samples/connect-oracle-xstream-task-failure.log` | 5 minutes of Connect worker log (10:01:03 → 10:05:55): a connector created with a wrong password (`ORA-01017`), one with an unknown outbound server, then a task failing after the outbound server was stopped with `DBMS_XSTREAM_ADM.STOP_OUTBOUND` |
| `connect_many_connectors` | `samples/connect-many-connectors.log` | written by hand in the formats of Connect (2026-11-06, 14 min, CP 8.1.2): 8 connectors on one worker, the JDBC Oracle sink killed on `ORA-00942`, the JDBC PostgreSQL source refused, S3 `Access Denied` with consumer rejoins, Elasticsearch malformed documents, the Debezium MySQL binlog purged (task killed), HTTP 503 retries exhausted (task killed), ServiceNow 429, a custom `com.acme` connector; 3 of them below the minimum version supported on CP 8.1: the 🔌 cards with their icons and 🛟 support, the ⛔ banner |
| `support_bundle` | `samples/support-bundle.zip` | that log and the broker log of the same period (gzipped), as a customer would attach them: shows the archive extraction and that only files with findings are listed |
| `broker_pressure` | `samples/broker-pressure/` | written by hand in the formats of a KRaft broker (CP 8.1, 2026-11-09, 1 h): the `server.log` of 3 brokers while broker 3 falls behind (40 ISR shrinks on brokers 1 and 2, fetch errors and request timeouts of follower 3, responses to clients already gone, the log cleaner of broker 2 dying on a segment too large), with `kafka-topics-describe.txt` (4 topics, broker 2 leading 4 of its 10 preferred partitions, 3 under-replicated, a topic with replication factor 1) and `kafka-log-dirs.txt` (broker 1 using 18 GB, a second log dir of broker 3 offline): the 🐢 broker signals and the 🗺️ cluster layout |
| `jvm_dumps` | `samples/connect-oracle-xstream-task-failure.log`, `../thread-analyzer/samples/jdk21-scenario-{1,2,3}.txt`, `../heap-analyzer/samples/session-cache-leak-1.hprof.gz` | the Connect log of `connect_task_failure` with the 3 thread dumps of the thread analyzer (a deadlock, 8 threads on one lock, a stuck task thread, a thread using a whole CPU, a growing pool) and a heap dump of the heap analyzer (not copied): the 🧵 🔬 JVM dumps card |
| `kafka_streams` | `samples/kafka-streams/` | the logs of the 3 instances of `other/kafka-streams/serde-errors.sh` (Kafka Streams 4.4.0): a demo application in ERROR after a poison pill, its dead stream thread, deserialization and production handler errors: the 🌊 Kafka Streams section of the report, and the Kafka Streams known causes (also `playground streams status --sample kafka_streams`) |
| `kafka_clients` | `samples/kafka-clients/` | real logs of the non-Java clients of `other/client-*` (2026-11-05, librdkafka 2.16.0, confluent-kafka-python 2.16.1, confluent-kafka-go 2.16.1, Confluent.Kafka 2.16.0, @confluentinc/kafka-javascript 1.11.0, kafkajs 2.2.4, Rust confluent-kafka): each client image run alone (`docker run --add-host broker:127.0.0.1`) against a port that refuses connections, a broker name that does not resolve (Go), with `message.timeout.ms=8000`, then with an unknown property (`bogus.property=1`). `synthetic-crashes/` are hand-written in the documented formats of the crashes the clients did not produce: .NET console logger and unhandled exception with an inner exception, Go panic, Rust panic, uncaught Node.js error with `[cause]`, chained Python tracebacks after a `logging.exception()` |
| `compare_fix` | `samples/compare/after.log` with `--compare samples/compare/before.log` | a Connect worker the day after a fix (2026-11-06) against the day before (2026-11-05), 9 minutes each, written by hand in the formats of Connect: the fenced producer, the throttling of S3 and the topic policy error gone, a new JDBC `SQLRecoverableException`, the offset commit failing in a rebalance 7 times instead of once: the 🔁 Comparison of `--compare` |
| `connect_workers` | `samples/connect-workers/` | synthetic (`samples/generate_synthetic_shapes.py`, 2026-11-10, 40 min, CP 8.1.2), the shapes of customer files: the `connect.log` of 2 workers, worker B writing each line twice (two appenders: ⚠️ duplicated lines collapsed), the graceful stop of `orders-cdc-0` failing on worker B and its errors going on there while worker A runs it (🧟 zombie task), an HDFS sink of worker A rotating with empty offsets and never committing (🔂 livelock, INFO lines only); `thread-dumps/`: 2 dumps of each worker in one folder (🧵 one analysis per JVM, a lock stall on worker B: the binlog keepalive thread waits for a `ReentrantLock` held by the binlog reader, RUNNABLE in a TLS socket write, in both dumps); `connectors-status.txt`: `/connectors?expand=status` saved with its shell prompt, the trace of the FAILED task of a third worker becomes a record |
| `loki_export` | `samples/grafana-loki-export.txt` | synthetic: a Grafana Explore "Download as txt" of a Loki query (its header with `Common labels: {…}`, `<epoch in ns>\t<UTC time>Z\t` before each line, newest first) of an S3 sink denied by S3: the prefix removed, ⚠️ newest-first, the times put back in order |
| `connector_cr` | `samples/connector-cr/` | synthetic: one CFK `Connector` custom resource next to the log of the worker saved as `.txt` (`kubectl logs connect-0 > connect-0.txt`): read as log files, not as a CFK support bundle |

Passwords are masked by Connect (`password=********`).

### Logs of the other clients

In the HTML report, `log_html()` of `tools/report-common/report_html.py` colors their lines like the Java ones: the
levels (librdkafka `%3|` / `FAIL`, `panic:`, `fatal error:`, .NET `fail:` / `crit:`, `Error:`), the librdkafka epoch
timestamp, the client context (`[rdkafka#producer-1]`, `[thrd:…]`, KafkaJS `[Connection]`, Java `[Producer clientId=…]`),
the exceptions without package (`KafkaException`, `KafkaError`), the librdkafka error codes (`_MSG_TIMED_OUT`) and errno
(`ECONNREFUSED`); the exception chains of the findings use it for anything that is not a Java `Exception: message`.

`summarize_log_errors` reads the levels and crashes of every Confluent client, not only Java: the librdkafka lines
(`%3|<epoch>|FAC|name| …`, syslog level 0-2 FATAL, 3 ERROR, 4 WARN, timestamp converted from the epoch, UTC, by
`epoch_iso()`), the Node.js objects of the JavaScript client logger (`js_rdkafka()`: `fac: 'FAIL'` / `'ERROR'`, written
back as the librdkafka line), the .NET console logger (`fail:` / `crit:`, message joined by `join_second()`) and inner
exceptions (` ---> `, a `Caused by:`), Python tracebacks (`mode == "py"`: the chained ones in one record, the chain
outermost first, the 3 last frames of the deepest cause; for Java, the first 3 frames of the deepest cause outside the
JDK: `java.*` / `javax.*` / `jdk.*` / `sun.*` frames, with or without their `java.base/` module, only when there is no
other, so that `com.ibm.as400.access.PortMapper.getSocketConnection` shows rather than `NioSocketImpl.connect`), Go panics (`mode == "go"`: the functions of the first
goroutine), Rust panics (message joined) and the uncaught `XxxError: …` lines of Node.js / Python / .NET. The record key
is masked (digits, ids) **before** it is cut to 200 characters. `log_report.py` takes the .NET (`` `2[…] `` generic
types), Python and Node.js exception names as root causes, and labels a librdkafka record `FAIL [rdkafka#producer-1]
<message>` and a JSON log line by its `message`.

```bash
playground analyze logs --sample connect_task_failure
playground analyze logs --sample support_bundle
```

The repository ignores `*.log`: `.gitignore` keeps `samples/*.log`.
