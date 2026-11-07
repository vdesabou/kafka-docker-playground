# log-analyzer

Samples and HTML report of `playground analyze logs`, the ERROR/FATAL digest of log files, folders and bundles. The
digest itself is plain bash (`scripts/cli/src/commands/analyze/logs.sh`, `summarize_log_errors` in
`scripts/cli/src/lib/cli_function.sh`): it de-duplicates records with an occurrence count and collapses stack traces
to their `Caused by:` chain.

`tools/log-analyzer/test_digest_awk.sh gawk mawk "busybox awk"` runs the digest on the samples with each awk and fails
when one of them errors or finds other records (the Tools tests workflow runs it): the digest must stay portable, mawk
(the default awk of Debian / Ubuntu) refuses a function and a parameter of the same name, for example.

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
offset are compared in UTC to detect a newest-first export. Tests: `python3 -I tools/log-analyzer/test_log_analyzer.py`, run with `tools/report-common/test_sanitizer.py` by the Tools tests workflow (`.github/workflows/tools-tests.yml`) on the pull requests that change `tools/log-analyzer/` or `tools/report-common/`.

## Without Docker, without the playground

`analyze logs` (and the other offline analyzers: `gc-logs`, `thread-dump`, `oracle-xstream-report`, plus `find-command`,
`find-example`) skip the container engine check of the CLI (`filter_docker_running`), and the CLI has no global `docker`
dependency anymore. It needs bash 4.2+, python3 3.8+ (standard library), the `jq` binary (checked with `type -P`: the `jq`
function of the playground runs it in a container), awk, gzip and tar. A `.zip` without `unzip` is extracted with
`python3 -m zipfile`. Without a container engine, a CFK bundle has no ☸️ sections (a warning, not a failure), its pod logs
are read. A shallow sparse clone of `scripts`, `tools` and `cfk-analysis` (about 33 MB) is enough: see "Without the
playground" in the deep dive.

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
`Progress` class is also used by `json_log_export.py` while it converts a large file.

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
versions). The header has a 🐳 kafka-docker-playground badge (`KDP_SITE`) and a ❓ How to generate this report link to
the deep dive page (`ANALYZE_LOGS_DOC`). Under the verdict, the quick links (`QUICK_LINKS`, filled by `KPI_LINKS` from the titles of
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
and the S key; all open the same dialog (.zip, summary, summary for a ticket, path, email).

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
logs, thread dumps or TLS debug output that explain a known cause (not when 🧰 found them in the input); the broker logs
when 💥 a burst follows a cluster event without them; and for the 3 most frequent ERROR root causes no known cause
explains, the DEBUG logger of the plugin (`debug_logger()`: the package, 4 parts at most, of the first frame of the record
or of its context that is not the JDK, the Connect runtime or the Kafka clients, else of its logger), with the
`PUT /admin/loggers` and log4j lines. Shown in the summary, the 📥 section of the HTML report, the summary for a ticket and
`.data_to_request` of `--json`.

## Tasks by worker (🖥️)

`task_workers()` reads the `task_start` events (`Starting task <connector>-<n>`, logged by the worker that runs the task,
whatever the rebalance protocol: the `taskIds` of `got assignment` only list the tasks added with the incremental
cooperative protocol) of each file. A worker is a file without its rotation suffix (`worker_of()`: `connect.log.1`,
`connect.log.2026-11-06-10`, `.gz`), shown by its folder when the folders tell the workers apart. With 2 workers or more:
`tasks[]` (the runs of each task: worker, from, to, starts), `connectors[]` (the workers of its tasks with their starts
and the ERROR / WARN of the connector in that worker's logs) and `only_on` when the errors (`ONLY_ON_MIN_ERRORS` = 3 or
more) all come from one worker while its tasks also ran on others. Shown in the summary, the 🖥️ section of the HTML
report (follows the connector filter, `pgLifecycle()`), the 🔌 card, the summary for a ticket and `.task_workers` of
`--json`.

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
fixed version of each line) and the pull request of the fix, which gives the exception and the frames to match.

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

The digest also notes the lifecycle of the INFO lines (`@@PGEVT@@` events, 300 per kind and file, and `@@PGEVTN@@` counts):
`Rebalance started` of a worker group, `Request joining group due to: <reason>` of a consumer group, `Starting connector`,
`Starting task` (its task id as detail), `Kafka Connect started` / `worker initialization took`, `Kafka Server started` / `Transition from
STARTING to STARTED`, the stops (`] shutting down (kafka.server`, `to SHUTTING_DOWN`, `Kafka Connect stopping`), the active
controller changes (`Becoming the active controller` of KRaft, `elected as the controller` of ZooKeeper) and the GC pauses
of 1 s or more of a GC log (`gc_pause`, detail `<ms> <what>`: unified `GC(12) Pause Full (…) … 2512.789ms`, legacy
`[Full GC …, 1.8234560 secs]`, the total before `[Times:`; a GC log decorated with the uptime only has no time, no event). `lifecycle()` counts them per group / connector with the rate per hour of the period covered and
marks a 🌀 storm (`STORM_MIN` = 10 at `STORM_PER_HOUR` = 6 or more, a consumer leaving on purpose excluded): the 🔄 Restarts
and rebalances section, a line on the 🔌 card of a connector, the (re)starts and the first 20 worker group rebalances in
the 🗓️ timeline, the terminal summary, the summary for a ticket and `.lifecycle` of `--json`.
The 🔄 section draws them over time (a zoomable chart, one series per kind) and each row has a swimlane of its
occurrences on the period of the table (`LC_BINS` = 120 buckets, a tick per bucket with occurrences, darker with more),
from the times noted (`_times` of each row, left out of `--json`). Logs that cover less than an hour (`.lifecycle.hours`) show
the count over that period (`10 in 5 min`) instead of an extrapolated rate per hour; only a 🌀 storm is red.
The 🔄 section follows the connector filter (`pgLifecycle()`): each row carries the connector it belongs to
(`lifecycle_connector()`: the connector or task started, the sink connector of a consumer group, as `data-conn`), the rows of
the other connectors are hidden and the worker group rebalances and process starts, which concern every connector of the
worker, stay.

## Knowledge-base articles

`LINKS` in `tools/report-common/known_causes.py` gives a known cause one or more Confluent support knowledge-base
articles (`kb`, `kb_title`) and / or a docs page (`docs`). A cause with several articles has a list; an article with a
`pattern` (case-insensitive regex) is about one variant of the cause and is shown only when a record of the cause matches
it, before the general ones (`MAX_KB_ARTICLES` = 3 at most; a general article marked `fallback`, too far from the
variants, only when none matched): ORA-01017, MySQL `Access denied for user` and SASL
`Invalid username or password` are three authentication failures with three articles. They are in `--json`
(`known_causes[].kb_articles`, and `kb` / `kb_title` for the first one), a `📚` line each in the terminal summary, the
What to do column of the summary for a ticket and the finding card of the HTML report. Only articles found in the
knowledge base for signed-in users (most GTS runbooks are internal), and only when they explain the cause (or the
variant) in general, not a connector that merely quotes the error in a stack trace: a cause without a good article has
no entry. Never build a URL by hand.

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
      📚 KB: "TimeoutException: expiring records for topic": https://support.confluent.io/hc/en-us/articles/32304589191444-How-to-resolve-the-TimeoutException-expiring-records-for-topic-producer-error
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
files in one chronological list: the first occurrence of each root cause (the record's own message, `record_label()`),
the first occurrence of each known cause (one row with the error when they are on the same line), the (re)starts of the
components (a `START_CONFIGS` dump logged at startup: `DistributedConfig`, `KafkaConfig`…), the connectors (re)configured
(once per connector and minute) and the config keys changed between restarts (`@@PGCFGCHG@@`). Only what has a
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
summary: the bundle may not even contain the incident. A records file written before that (no field 5 and 6) falls
back to the span of the records.
`log_report.py` reads it and writes the HTML report (`--html-out`) or prints the analysis (`--json`): known causes
(task killed, with one line per distinct exception chain of the killed tasks, authentication, cloud credentials (an AWS
`SignatureDoesNotMatch` or `(Service: S3, Status Code: 403`), TLS, unknown magic byte,
`OutOfMemoryError`…, each pointing at its earliest occurrence; the list is shared with the CFK analyzer, in
`tools/report-common/known_causes.py`), occurrences over time, 🗂️ the files with findings (a 📁 header per folder, a card
per file with its component, the occurrences with a bar split by level, the levels as pills, also in the title of the card of each
file; `pgFilesTable()` counts them again for the filters), root causes
(deepest exception of each record) and every record (with a 📋 Show context block: the raw lines around its first
occurrence, from the `@@PGCTX@@` lines of the records file) and the ⚙️ configuration (the `<Class>Config values:`
dumps of the logs, from the `@@PGCFG@@` / `@@PGCFGL@@` blocks, with the keys changed between two dumps of the same
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
`pgStateWrite()` / `pgStateRead()`, the URL wins over the component remembered in `localStorage`): 🔗 **Link to this view**
copies it, and the link opens the report on the same view. These
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
| `kafka_streams` | `samples/kafka-streams/` | the logs of the 3 instances of `other/kafka-streams/serde-errors.sh` (Kafka Streams 4.4.0): a demo application in ERROR after a poison pill, its dead stream thread, deserialization and production handler errors: the 🌊 Kafka Streams section of the report, and the Kafka Streams known causes (also `playground streams status --sample kafka_streams`) |

| `kafka_clients` | `samples/kafka-clients/` | real logs of the non-Java clients of `other/client-*` (2026-11-05, librdkafka 2.16.0, confluent-kafka-python 2.16.1, confluent-kafka-go 2.16.1, Confluent.Kafka 2.16.0, @confluentinc/kafka-javascript 1.11.0, kafkajs 2.2.4, Rust confluent-kafka): each client image run alone (`docker run --add-host broker:127.0.0.1`) against a port that refuses connections, a broker name that does not resolve (Go), with `message.timeout.ms=8000`, then with an unknown property (`bogus.property=1`). `synthetic-crashes/` are hand-written in the documented formats of the crashes the clients did not produce: .NET console logger and unhandled exception with an inner exception, Go panic, Rust panic, uncaught Node.js error with `[cause]`, chained Python tracebacks after a `logging.exception()` |
| `compare_fix` | `samples/compare/after.log` with `--compare samples/compare/before.log` | a Connect worker the day after a fix (2026-11-06) against the day before (2026-11-05), 9 minutes each, written by hand in the formats of Connect: the fenced producer, the throttling of S3 and the topic policy error gone, a new JDBC `SQLRecoverableException`, the offset commit failing in a rebalance 7 times instead of once: the 🔁 Comparison of `--compare` |

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
outermost first, the 3 last frames of the deepest cause), Go panics (`mode == "go"`: the functions of the first
goroutine), Rust panics (message joined) and the uncaught `XxxError: …` lines of Node.js / Python / .NET. The record key
is masked (digits, ids) **before** it is cut to 200 characters. `log_report.py` takes the .NET (`` `2[…] `` generic
types), Python and Node.js exception names as root causes, and labels a librdkafka record `FAIL [rdkafka#producer-1]
<message>` and a JSON log line by its `message`.

```bash
playground analyze logs --sample connect_task_failure
playground analyze logs --sample support_bundle
```

The repository ignores `*.log`: `.gitignore` keeps `samples/*.log`.
