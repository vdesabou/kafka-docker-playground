# log-analyzer

Samples and HTML report of `playground analyze logs`, the ERROR/FATAL digest of log files, folders and bundles. The
digest itself is plain bash (`scripts/cli/src/commands/analyze/logs.sh`, `summarize_log_errors` in
`scripts/cli/src/lib/cli_function.sh`): it de-duplicates records with an occurrence count and collapses stack traces
to their `Caused by:` chain.

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

## Progress of large inputs

`progress.py` shows the progress of a large input: `cat` copies stdin to the digest with a bar on stderr (terminal
only, 20 MB or more), `page` writes the 🔄 progress page opened in the browser at the path of the report (reloaded
every 2 s; `log_report.py` writes the report next to it then renames it), `size` and `human` give the size of the
input. The page and the overall progress come from `PG_PROGRESS_*` variables exported by `analyze logs`; the
`Progress` class is also used by `json_log_export.py` while it converts a large file.

## Overview of logs without findings

`log_overview.py --records <records> --sources <sources> [--exports <exports>] [--json]` runs when no file has a
finding: lines, period covered (the `@@PGFILE@@` timestamps of the digest) and records by level of each file, the most
frequent messages (masked: numbers, hex ids, UUIDs) and loggers, and hints (period shorter than 10 min, only
INFO/DEBUG records, an export of a log console cut at its size limit). `analyze logs` prints it, adds it to the HTML
report (🔭 Overview section) and to `--json` (`.overview`).

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
summary: the bundle may not even contain the incident. A records file written before that (no field 5 and 6) falls
back to the span of the records.
`log_report.py` reads it and writes the HTML report (`--html-out`) or prints the analysis (`--json`): known causes
(task killed, with one line per distinct exception chain of the killed tasks, authentication, cloud credentials (an AWS
`SignatureDoesNotMatch` or `(Service: S3, Status Code: 403`), TLS, unknown magic byte,
`OutOfMemoryError`…, each pointing at its earliest occurrence; the list is shared with the CFK analyzer, in
`tools/report-common/known_causes.py`), occurrences over time, root causes
(deepest exception of each record) and every record (with a 📋 Show context block: the raw lines around its first
occurrence, from the `@@PGCTX@@` lines of the records file) and the ⚙️ configuration (the `<Class>Config values:`
dumps of the logs, from the `@@PGCFG@@` / `@@PGCFGL@@` blocks, with the keys changed between two dumps of the same
config from the `@@PGCFGCHG@@` lines, and the `.properties` / connector JSON files that `analyze logs` appends), with a
level and connector filter (connector taken from the
`[connector|task-0]` / `[connector|worker]` context of the line, also with a scope like `[connector|task-0|redoLog]`, or `WorkerSinkTask{id=connector-0}`)
and a period filter (drag over the 📈 occurrences chart). The three filters drive **everything below the filter bar**
from one index of records written once in the page, `occurrences_json()`: `<script type="application/json"
id="pg-occurrences">` holds `[root cause index, level, connector index, occurrences, epoch seconds, record index, file
index]` per record, the times being the first value then the deltas in base 36 (`encode_times()` / `pgTimes()`). On
each change `FILTER_SCRIPT` counts them again and redraws the 📈 chart (`window.pgChartTimes()` builds its series and
`box.setTimes()` of `zoom_chart.js` draws them, the x axis pinned by `xmin` / `xmax`), the 🔝 top causes bars, the 🌳
root causes rows (`tr.rc-row[data-cause]`), the 🗂️ files rows (`tr.file-row[data-file]`) and the record blocks
(`details[data-rec]`, `.rec-count`). The period comes from the `zoomchange` event of the chart (id
`occurrences-chart`). The 🔎 findings are the exception: their text is never rewritten (it is the diagnosis of the
bundle), each card only gets `▸ N of M occurrence(s) here` in its `.rec-scope` span, or is dimmed (`.out`) when none
of it is in the selection - from the `data-recs` indexes that `findings_html()` writes for an item with `records`. Occurrences beyond the 1000 kept per record have no time of their own: they count in the totals
but not in a period, and the legend of the root causes says how many there are.
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
| `support_bundle` | `samples/support-bundle.zip` | that log and the broker log of the same period (gzipped), as a customer would attach them: shows the archive extraction and that only files with findings are listed |
| `kafka_streams` | `samples/kafka-streams/` | the logs of the 3 instances of `other/kafka-streams/serde-errors.sh` (Kafka Streams 4.4.0): a demo application in ERROR after a poison pill, its dead stream thread, deserialization and production handler errors: the 🌊 Kafka Streams section of the report, and the Kafka Streams known causes (also `playground streams status --sample kafka_streams`) |

| `kafka_clients` | `samples/kafka-clients/` | real logs of the non-Java clients of `other/client-*` (2026-11-05, librdkafka 2.16.0, confluent-kafka-python 2.16.1, confluent-kafka-go 2.16.1, Confluent.Kafka 2.16.0, @confluentinc/kafka-javascript 1.11.0, kafkajs 2.2.4, Rust confluent-kafka): each client image run alone (`docker run --add-host broker:127.0.0.1`) against a port that refuses connections, a broker name that does not resolve (Go), with `message.timeout.ms=8000`, then with an unknown property (`bogus.property=1`). `synthetic-crashes/` are hand-written in the documented formats of the crashes the clients did not produce: .NET console logger and unhandled exception with an inner exception, Go panic, Rust panic, uncaught Node.js error with `[cause]`, chained Python tracebacks after a `logging.exception()` |

Passwords are masked by Connect (`password=********`).

### Logs of the other clients

`summarize_log_errors` reads the levels and crashes of every Confluent client, not only Java: the librdkafka lines
(`%3|<epoch>|FAC|name| …`, syslog level 0-2 FATAL, 3 ERROR, 4 WARN, timestamp converted from the epoch, UTC, by
`epoch_iso()`), the Node.js objects of the JavaScript client logger (`js_rdkafka()`: `fac: 'FAIL'` / `'ERROR'`, written
back as the librdkafka line), the .NET console logger (`fail:` / `crit:`, message joined by `join_second()`) and inner
exceptions (` ---> `, a `Caused by:`), Python tracebacks (`mode == "py"`: the chained ones in one record, the chain
outermost first, the 3 last frames of the deepest cause), Go panics (`mode == "go"`: the functions of the first
goroutine), Rust panics (message joined) and the uncaught `XxxError: …` lines of Node.js / Python / .NET. The record key
is masked (digits, ids) **before** it is cut to 200 characters. `log_report.py` takes the .NET (`` `2[…] `` generic
types), Python and Node.js exception names as root causes, and labels a librdkafka record `FAIL [rdkafka#producer-1]
<message>` and a JSON log line by its `message`.

```bash
playground analyze logs --sample connect_task_failure
playground analyze logs --sample support_bundle --include-warnings
```

The repository ignores `*.log`: `.gitignore` keeps `samples/*.log`.
