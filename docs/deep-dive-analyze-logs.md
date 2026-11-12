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
| the same report for the running example | `playground analyze logs --from-containers` (`--container <c>` to keep some) |
| only one connector | `… --connector <name>` (`--with-worker` to keep the worker records) |
| the configuration a component logged at startup | `… --show-config <connector\|config class\|client id>` |
| whether the fix worked | `playground analyze logs -f <after> --compare <before>` |
| something to paste in a ticket outside Confluent | `… --sanitize` |
| JSON for `jq`, a script or an agent | `… --json [--json-sections summary,known_causes,timeline]` |
| to try it now | `playground analyze logs --sample support_bundle` |
| someone without the playground to run it (a customer, a colleague) | `docker run --rm --network none -v "$PWD":/data ghcr.io/vdesabou/kdp-analyze-logs -f <path>`: [🐳 with nothing installed but Docker](deep-dive-analyze-logs.md?id=🐳-with-nothing-installed-but-docker) |

## 🐳 With nothing installed but Docker

The same `analyze logs`, packaged as an image: **`ghcr.io/vdesabou/kdp-analyze-logs`**. Anyone with Docker can run it
on their own logs: a customer before sending a bundle, a colleague of another team, a partner, Windows without WSL, a
locked-down laptop. No git, no clone, no bash 4, no python, no jq, no login: the image is public (linux/amd64 and
linux/arm64, Apple silicon included).

From the folder that holds the logs:

```bash
# macOS / Linux
docker run --rm --network none -v "$PWD":/data -e KDP_HOST_DIR="$PWD" ghcr.io/vdesabou/kdp-analyze-logs -f case-12345-bundle.zip --sanitize
```

```powershell
# Windows PowerShell (no WSL needed)
docker run --rm --network none -v "${PWD}:/data" -e KDP_HOST_DIR="${PWD}" ghcr.io/vdesabou/kdp-analyze-logs -f case-12345-bundle.zip --sanitize
```

The report, the summary for a ticket and the 📤 Share `.zip` are written in `./log-analysis-output/`, on the host. Open
the path printed after `🔗 Open in browser` (there is no browser in a container). Every flag of this page works the same:
`-f` repeated, a folder, `--connector`, `--compare`, `--since`, `--json`…

To try it without a bundle, on a sample shipped in the image:

```bash
cd /tmp && docker run --rm --network none -v "$PWD":/data -e KDP_HOST_DIR="$PWD" ghcr.io/vdesabou/kdp-analyze-logs --sample support_bundle
```

(`--sample cfk_bundle` for a CFK support bundle, `--sample cfk_rollout --sample cfk_rollout_after` for two bundles compared.)

| Part of the command | Why |
| --- | --- |
| `-v "$PWD":/data` | the folder of the logs: the paths of `-f` are relative to it, and the report is written in it. A file outside it (`../x.zip`, another absolute path) is not seen: run the command from a folder that holds everything |
| `--network none` | the analysis needs no network: **the logs cannot leave the machine**, and Docker enforces it, it is not just a promise |
| `-e KDP_HOST_DIR="$PWD"` | optional: the paths printed and the ✏️ links of the report (open a file at the line in VS Code) are those of the host. Without it, the paths are printed relative to the folder and the report has no ✏️ link |
| `--sanitize` | secrets, IPs, hostnames, emails and LDAP DNs replaced by placeholders, in the report, the summary and `--json`. Best effort: review before sharing |
| `--user "$(id -u):$(id -g)"` | add it on Linux, so that the report belongs to you and not to root (Docker Desktop on macOS and Windows does it already) |

Good to know:

- **CFK support bundles** get their ☸️ sections (pods, custom resources, events, versions, recent changes) in the image,
  as with the playground: nothing else to install.
- **Updates**: `docker pull ghcr.io/vdesabou/kdp-analyze-logs`. It is rebuilt on each change of the analysis and every
  week. To name or pin the version used in a case, use the `:<date>` (`:2026-11-09`) or `:<commit sha>` tags.
- **Which version is it?** `docker image inspect ghcr.io/vdesabou/kdp-analyze-logs --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'`
  gives the commit of kafka-docker-playground it was built from.

The image is built from [`tools/analyze-logs-image`](https://github.com/vdesabou/kafka-docker-playground/tree/master/tools/analyze-logs-image),
then tested and published by the `analyze logs image` workflow.

## ⭐ Why it changes a support case

- **One command, whatever the customer sent**: a zip / tar / 7z bundle, folders of rotated logs, `.gz` files, a CFK
  support bundle, a CloudWatch, OpenSearch, Kibana, Splunk or Datadog export (JSON, CSV), logs pasted in a Word
  document or exported to Excel, the logs of a Python, Go, .NET, JavaScript or Rust client, Kafka Streams instances.
- **An answer, not 40,000 lines**: the verdict and the 📖 story (first error, peak, main cause, still failing?), the
  known causes with what to do and the 📚 KB article, every distinct error grouped by its deepest exception.
- **What came first**: one timeline of every file, the errors right after a restart, a config change or a GC pause,
  the restarts and rebalances with a link to each line.
- **Per connector**: its errors, its plugin version against the minimum supported and the changelog since, the
  configuration it logged, a config lint.
- **Every line, offline**: a search of every line of the logs (INFO included) in the browser, a period picked like in
  Grafana.
- **Did the fix work?** `--compare` with the logs before it, or two CFK bundles.
- **Ready to share**: the `.zip` of the report, a sanitized summary for a ticket, Slack or rich text, a link to a view;
  `--sanitize` for outside Confluent; `--json` for scripts and agents.
- **Nothing to install**: awk and the Python standard library; the report is one HTML file that opens offline (Docker
  only for the ☸️ sections of a CFK bundle).

## 📸 A tour of the report

Each screenshot is a section of a real report, generated from the samples of the playground: click it to open the
report on that section and try it (filters, zoom, search, links to the lines).

<div class="report-tour">
<figure><a href="reports/logs/support_bundle-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-story.png" alt="📖 What happened, at a glance" loading="lazy"></a><figcaption><b>📖 What happened, at a glance</b>The verdict, the story of the logs (first error, peak, main cause, still failing at the end?), the versions and their end of support, the findings by severity.</figcaption></figure>
<figure><a href="reports/logs/support_bundle-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-findings.png" alt="🔎 Findings: what to look at first" loading="lazy"></a><figcaption><b>🔎 Findings: what to look at first</b>The known causes with what to do, a 📚 KB article and the internal runbooks, then the most frequent errors no known cause explains, with their exception chain.</figcaption></figure>
<figure><a href="reports/logs/support_bundle-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-filters.png" alt="🕐 Filters and the period" loading="lazy"></a><figcaption><b>🕐 Filters and the period</b>Levels, component, connector, a search, and a period picked like in Grafana (quick ranges from the end of the logs, from → to with a 📅 picker, around a time): every section follows, and the URL keeps it.</figcaption></figure>
<figure><a href="reports/logs/support_bundle-log-report.html#incident-timeline" target="_blank" rel="noopener"><img src="images/reports/logs-tour-timeline.png" alt="🗓️ Incident timeline" loading="lazy"></a><figcaption><b>🗓️ Incident timeline</b>What happened first, all files merged: first errors, known causes, restarts, connectors reconfigured, config changes, GC pauses, a lane per component; drag to zoom, ⏱️ for ± 2 min around an event.</figcaption></figure>
<figure><a href="reports/logs/support_bundle-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-occurrences.png" alt="📈 Occurrences over time" loading="lazy"></a><figcaption><b>📈 Occurrences over time</b>ERROR / WARN over time, zoom down to the second (a burst of a few seconds in a 3-day bundle), and the top root causes next to it.</figcaption></figure>
<figure><a href="reports/logs/support_bundle-log-report.html#all-root-causes" target="_blank" rel="noopener"><img src="images/reports/logs-tour-root-causes.png" alt="🌳 Every distinct error" loading="lazy"></a><figcaption><b>🌳 Every distinct error</b>Grouped by deepest exception, with its occurrences, files, connectors and the finding that explains it: the long tail.</figcaption></figure>
<figure><a href="reports/logs/support_bundle-log-report.html#pg:lq=level%3AINFO" target="_blank" rel="noopener"><img src="images/reports/logs-tour-search.png" alt="🔎 Search every log line" loading="lazy"></a><figcaption><b>🔎 Search every log line</b>INFO and DEBUG included, in the browser, offline: <code>level:</code>, <code>file:</code>, <code>comp:</code>, <code>/regex/</code>, a histogram of the matches (drag: the period), a click for the lines around one.</figcaption></figure>
<figure><a href="reports/logs-many-connectors/connect_many_connectors-log-report.html#connectors" target="_blank" rel="noopener"><img src="images/reports/logs-tour-connectors.png" alt="🔌 A card per connector" loading="lazy"></a><figcaption><b>🔌 A card per connector</b>Errors, task kills, known causes, the plugin version (below the minimum supported?) with its changelog since that version, its configuration; ▶ only this connector.</figcaption></figure>
<figure><a href="reports/logs-many-connectors/connect_many_connectors-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-rebalances.png" alt="🔄 Restarts and rebalances" loading="lazy"></a><figcaption><b>🔄 Restarts and rebalances</b>Worker group rebalances, consumer group rejoins with their reason, task starts, 🌀 storms; a click on a row shows it alone and lists each occurrence with a link to its line.</figcaption></figure>
<figure><a href="reports/logs-many-connectors/connect_many_connectors-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-config.png" alt="⚙️ The configuration logged" loading="lazy"></a><figcaption><b>⚙️ The configuration logged</b>The configs each component logged at startup, the keys changed between restarts, a config lint, the Connector CR of a CFK bundle compared with the config the worker logged.</figcaption></figure>
<figure><a href="reports/logs-connect/connect_task_failure-log-report-files/001-connect-oracle-xstream-task-failure.log.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-file-page.png" alt="📄 The log file itself" loading="lazy"></a><figcaption><b>📄 The log file itself</b>Every file with findings has its page: line numbers, the findings highlighted, ▲ ▼ to go from one to the next. Each file:line of the report opens it.</figcaption></figure>
<figure><a href="reports/logs-compare/compare_fix-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-compare.png" alt="🔁 Did the fix work?" loading="lazy"></a><figcaption><b>🔁 Did the fix work?</b><code>--compare &lt;before&gt;</code>: the root causes, known causes and connectors new, gone, growing or shrinking, per hour when the periods differ; a trend over several inputs.</figcaption></figure>
<figure><a href="reports/logs-streams/kafka_streams-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-streams.png" alt="🌊 Kafka Streams" loading="lazy"></a><figcaption><b>🌊 Kafka Streams</b>The instances of a Streams application: their states over time, rebalances, the tasks, the stream threads that died, the known Streams errors with what to do.</figcaption></figure>
<figure><a href="reports/cfk-bundle/cfk_bundle-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-cfk.png" alt="☸️ A CFK support bundle" loading="lazy"></a><figcaption><b>☸️ A CFK support bundle</b>Pods, custom resources, events and pod logs in one report: the ☸️ issues as findings (crash loops, OOMKilled, certificates, pending volumes), the versions of CFK and CP.</figcaption></figure>
<figure><a href="reports/logs-jvm-dumps/jvm_dumps-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-jvm-dumps.png" alt="🧵 🔬 JVM dumps of the input" loading="lazy"></a><figcaption><b>🧵 🔬 JVM dumps of the input</b>The thread dumps of the input analyzed in the report (deadlock, contention, stuck threads, CPU per thread between dumps), a link to the full thread report, and the command to analyze each heap dump.</figcaption></figure>
<figure><a href="reports/logs-broker-pressure/broker_pressure-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-broker-signals.png" alt="🐢 Broker signals" loading="lazy"></a><figcaption><b>🐢 Broker signals</b>ISR shrinks and expands by broker with their partitions, followers failing to fetch, requests timed out, the log cleaner that died: 🌀 storms, and their bursts on the timeline.</figcaption></figure>
<figure><a href="reports/logs-broker-pressure/broker_pressure-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-cluster-layout.png" alt="🗺️ Cluster layout" loading="lazy"></a><figcaption><b>🗺️ Cluster layout</b>From the kafka-topics --describe and kafka-log-dirs outputs of the bundle: replicas, leaders and disk per broker, non-preferred leaders, under-replicated partitions, a log dir offline, the disk skew.</figcaption></figure>
<figure><a href="reports/logs-cfk-rollout/cfk_rollout-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-cfk-compare.png" alt="🔀 Two CFK bundles compared" loading="lazy"></a><figcaption><b>🔀 Two CFK bundles compared</b>Same cluster?, the versions, the custom resources changed between them, the issues fixed, new or still there.</figcaption></figure>
<figure><a href="reports/logs/support_bundle-log-report.html" target="_blank" rel="noopener"><img src="images/reports/logs-tour-share.png" alt="📤 Share it" loading="lazy"></a><figcaption><b>📤 Share it</b>The .zip of the report and its pages, a sanitized summary for a ticket (Markdown), for Slack or as rich text, the path, an email. 🔗 Link to this view opens the report on the same filters.</figcaption></figure>
</div>

## 🗂️ Example reports

| Example | What it shows | Try it | Report |
| --- | --- | --- | --- |
| 🔥 A support bundle | brokers and Connect zipped together, a task killed, an Oracle error, the known causes | `playground analyze logs --sample support_bundle --include-warnings` | [open](reports/logs/support_bundle-log-report.html) |
| 🔌 A connector task killed | one Connect worker log, the exception chain, the configuration logged | `playground analyze logs --sample connect_task_failure` | [open](reports/logs-connect/connect_task_failure-log-report.html) |
| 🧩 A worker with many connectors | a card per connector, versions below the minimum supported, restarts and rebalances, config lint | `playground analyze logs --sample connect_many_connectors` | [open](reports/logs-many-connectors/connect_many_connectors-log-report.html) |
| 🧰 Non-Java clients | librdkafka, Python, Go, .NET, JavaScript and Rust clients, their versions | `playground analyze logs --sample kafka_clients` | [open](reports/logs-clients/kafka_clients-log-report.html) |
| 🌊 Kafka Streams instances | the states of three instances, a poison pill, a stream thread that died | `playground analyze logs --sample kafka_streams` | [open](reports/logs-streams/kafka_streams-log-report.html) |
| 🔁 Did the fix work? | the day after a fix compared with the day before | `playground analyze logs --sample compare_fix` | [open](reports/logs-compare/compare_fix-log-report.html) |
| ☸️ A CFK support bundle | the ☸️ issues of the cluster and the errors of the pods in one report | `playground analyze logs --sample cfk_bundle` | [open](reports/cfk-bundle/cfk_bundle-log-report.html) |
| 🔀 Two CFK bundles of a rollout | the bundles before and after a rollout compared | `playground analyze logs --sample cfk_rollout --sample cfk_rollout_after` | [open](reports/logs-cfk-rollout/cfk_rollout-log-report.html) |
| 🦘 A CFK KRaft migration | a ZooKeeper to KRaft migration that does not finish | `playground analyze logs --sample cfk_kraft_migration` | [open](reports/logs-cfk-kraft-migration/cfk_kraft_migration-log-report.html) |

All the reports of the playground are in the [📊 reports gallery](reports.md).

---

## 1. Mental model (the 4 things to remember)

1. **A digest, not a grep.** Every record with an explicit level (`ERROR`, `[ERROR]`, `level=error`, a librdkafka
   `%3|`, a Python traceback, a Go panic…) is kept, de-duplicated with an occurrence count, and its stack trace is cut
   to its `Caused by:` chain plus 3 frames of the deepest cause. 1.1 million `failed authentication` lines of 321
   connectors become **one** record with a count. INFO lines that merely contain "error" never count, and neither do
   the warnings of the JDK launcher on stderr (`WARNING: A terminally deprecated method in sun.misc.Unsafe has been
   called`, `WARNING: Use --enable-native-access=ALL-UNNAMED…`). 🙈 **Known harmless** records (telemetry not set up:
   `Unable to submit events without credentials`; Self-Balancing on a KRaft controller node; Jersey `A provider …
   registered in SERVER runtime…`) are left out of the findings and the counts, and listed in a 🙈 Known harmless
   section with why; `--include-harmless` keeps them.
2. **Known causes first.** About 50 known causes (task killed, `errors.tolerance` exceeded, authentication, TLS, wrong
   `security.protocol`, unknown magic byte, fenced producer, rebalances, throttling, records not delivered in time, a
   Connect worker that fails to start, a config provider placeholder `${secret:…}` that reached a connector…)
   are recognized and come with **what to do**, often the `playground` command that checks it, and for most of them
   📚 Confluent knowledge-base articles to read or send (in the terminal, the HTML report and the summary for a
   ticket): the article of the variant found in the logs first (ORA-01017, `Login failed for user`, SASL with
   librdkafka, `_confluent-command`, OOMKilled…), then the general one. With the private `reproduction-models` repository of Confluent support, the internal GTS runbooks (PKIX,
   SASL, authorization, converters, DLQ, consumer rebalancing…) come with a 🔒, in the terminal, the HTML report and
   `--json`, never in the summary for a ticket (`PLAYGROUND_LOG_RUNBOOKS_FILE`, default
   `reproduction-models/_miscellaneous/log-analysis/runbooks-internal.json`). Everything else is in the 🌳 root
   causes, grouped by deepest exception. 🌅 Connection failures that only happen while a component starts (its
   readiness check and its clients retry until the broker is up, then stop) are a LOW known cause of their own,
   **Connections retried while starting**: the HIGH 🔌 Connection failure keeps the ones that last or come back
   (same for host names not resolved yet). 🌐 **Host name not resolved (DNS)** is a known cause of its own, with what
   tells a DNS outage from a wrong name: the window (and whether the errors stopped before the end of the logs), the
   hosts, how many Java lookups failed in the resolver of the OS (`UnknownHostException: <host>: Name or service not
   known`) and how many were served from the negative cache of the JVM (`UnknownHostException: <host>` alone: one
   failed lookup handed to every client of the process for `networkaddress.cache.negative.ttl`), and the Java clients
   that could not be created (`No resolvable bootstrap urls given in bootstrap.servers`, thrown by the constructor and
   not retried: it kills the Oracle CDC source, which commits its redo log offsets with a new consumer). 🧬 **Not
   enough replicas** lists the partitions refused with their window (first → last, duration), ISR and min.isr, most
   refused first, and spots a single replica in sync while min.isr is 2: either the other replicas fell out of sync, or
   the topic has fewer replicas than `min.insync.replicas` (RF=1 with `min.insync.replicas=2` works until a replica is
   added by an RF increase, a reassignment or a Self-Balancing move, then every `acks=all` write is refused until the
   new replica has caught up). 🧹 **Clients
   aborted while a task stopped** (`Failed to close fetcher with a timeout`, `Producer is closed forcefully.`) is LOW:
   a consequence of the stop, not a root cause.
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
[🔌 a Connect worker](reports/logs-connect/connect_task_failure-log-report.html).

A worker that runs many connectors, each failing its own way, is `--sample connect_many_connectors` (CP 8.1.2, 8
connectors: JDBC, S3, Elasticsearch, Debezium MySQL, HTTP, ServiceNow, a custom one). Each 🔌 card has the icon of its
type and 🛟 its plugin version against the minimum supported on the CP release of the worker, and the ⛔ banner at the top
of the report lists the ones below it:

```text
🛟 3 connector(s) below the minimum version supported on CP 8.1: s3-sink 10.5.13 < 11.0.2, http-sink 1.7.6 < 1.7.10, jdbc-oracle-sink 10.7.4 < 10.8.4 (https://docs.confluent.io/platform/8.1/connect/supported-connector-version.html)
[HIGH] 🧨 A connector task was killed ×3 in connect-many-connectors.log (first at line 179, 2026-11-06 09:02:20)
🔌 Connectors (8, most errors first)
```

---

## 3. What it reads

Give it anything: `-f` takes files, folders and archives, repeated as many times as needed.

| Input | What happens |
| --- | --- |
| a folder | scanned recursively, sorted; `__MACOSX/`, `.DS_Store` ignored; a copy of a file already analyzed is skipped (`⏭️ … same content as …`); an overlapping copy of the same log (downloaded twice at two times, as the last 5000 lines of a connector log of the Confluent Cloud UI) only has its other lines analyzed (`✂️ … of its … lines are also in …`), and both are one worker (✂️ note in 🕰️ Log coverage) |
| `.zip`, `.tar`, `.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`, `.7z` | extracted to a temporary folder, nested archives too (`.7z` needs `bsdtar` or 7-Zip). An archive that does not fully extract is reported ⚠️ |
| `.gz` | decompressed on the fly; a truncated one (a partial download) is read up to the error and reported ⚠️ |
| a JSON export of log events: CloudWatch Logs Insights, CloudWatch events, Elasticsearch / OpenSearch hits (`_source` or `fields`), the Loki query API, structured JSON logs (logback, pino, bunyan, GELF: numeric levels too) | converted back to log lines, **oldest first**, stack traces below their event, then digested like a log file |
| the logs of a fully managed connector (`confluent connect logs --output-file`, keys `Timestamp`, `Level`, `TaskId`, `Message`, `Exception`; or `-o json`) | converted like a JSON export, the stack trace of `Exception` / `exception.stacktrace` kept; `playground connector logs -c <name> --analyze` fetches every page and adds the `[<name>\|task-0]` context, so the 🔌 card and `--connector` work as for a worker log |
| a CSV export (Kibana / OpenSearch Discover, Splunk `_time,_raw`, Datadog, Grafana) | one event per row, converted the same way |
| JSON lines whatever the extension (a fluentd / Kubernetes dump saved as `.log`) | detected and streamed: 2.4 GB in about 10 s |
| `journalctl` exports | the `Nov 03 18:29:20 host connect[1080]:` prefix is skipped to find the log4j timestamp |
| the logs of the C/C++, Python, Go, .NET, JavaScript and Rust clients | librdkafka `%3\|…\|FAIL\|` lines, Python tracebacks, Go and Rust panics, .NET `fail:` / `crit:` and inner exceptions, KafkaJS errors |
| Kafka Streams logs (`stream-client [`, `stream-thread [`) | the digest, plus a 🌊 **Kafka Streams** section: state of each instance over time, rebalances, tasks, restores |
| a CFK support bundle | analyzed as a whole by the CFK analyzer: pods, custom resources, events, versions, recent changes, see [the CFK deep dive](deep-dive-cfk.md); its ☸️ sections come right after the verdict of the log report (one report). Its pod and operator logs (`*.log`) also go through the digest: the regular log report (root causes, timeline, connectors, versions, tasks by worker, known bugs, data to request, summary for a ticket), linked by a 🔥 Log analysis banner at the top of the report of the bundle, which stays the one opened when the input is only bundles; with `--json`, `.log_analysis` of the bundle JSON. `--logs-only`: only the log report, of every file of the bundle |
| `.properties`, connector JSON (`/connectors?expand=info`), the output of `GET /connector-plugins` | shown in the ⚙️ configuration of the report; `/connector-plugins` gives its version to a 🔌 card without `Instantiated connector` line (changelog and support check) |
| thread dumps (jstack, `jcmd Thread.print`, also printed by `kill -3` in a stdout log) | 🧵 **analyzed in the report**, by the thread dump analyzer of `playground analyze thread-dump` run in the same process: deadlocks, lock contention, threads stuck on the same frames, CPU per thread between dumps of the same JVM, growing pools, Connect task threads and broker request handlers. Its findings are in 🧵 🔬 **JVM dumps of the input**, right after the verdict (the worst one in the verdict), each dump is on the 🗓️ timeline, and the full thread report is written next to the log report (`<input>-thread-dumps.html`, in the 📤 `.zip`). Also `.thread_dumps` of `--json` |
| heap dumps (`.hprof`, `.hprof.gz`) | not analyzed in the report (Eclipse MAT runs in Docker and needs about as much memory as the dump): 🧵 🔬 **JVM dumps of the input** gives the `playground analyze heap-dump` command of each at the top of the report, and the verdict says to run it. Also `.heap_dumps` of `--json` |
| the output of `kafka-topics --describe` and of `kafka-log-dirs --describe` (any file name, found by content) | 🗺️ **Cluster layout**: replicas and leaders per broker, the partitions led by a replica that is not the preferred one (above `leader.imbalance.per.broker.percentage`, 10%), leader and partition skew, offline, under-replicated and under `min.insync.replicas` partitions, topics with replication factor 1, a broker in no ISR (the 👁️ observers of a Multi-Region Cluster, `Observers: 4,5`, are counted apart: out of the ISR is their normal state); the disk used per broker and log dir (`—` for a broker of the replicas missing from `kafka-log-dirs`: a broker down), a log dir with an error (offline), the disk usage skew, the biggest partitions and topics, the replicas being moved. Also `.cluster_layout` of `--json` |
| GC logs, thread dumps, heap dumps, flight recordings (`.jfr`), network captures (`.pcap`, `.pcapng`), Oracle XStream diagnostics reports (`orclcdc_diag*.html`) | recognized by their content or name: 🧰 **Other files of the input** gives the `playground analyze gc-logs\|thread-dump\|heap-dump\|flight-recorder\|tcp-dump\|oracle-xstream-report` command to run on each (one command for the rotated GC logs of a folder). The ones extracted from an archive are kept in `<input>-other-files/` next to the report: the temporary folder is deleted at the end. Also `.other_files` of `--json` (where nothing is kept: the command says to extract the archive first) |
| any other binary file | skipped, counted in the last line |

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
   [HIGH] 🌐 Host name not resolved (DNS) ×23 in go-producer.log (first at line 2, 2026-11-05 16:28:49)
      🕐 2026-11-05 16:28:49 → 16:28:56 (7 s), still failing at the end of the logs
      🖥️ host(s) not resolved: nonexistent-broker
   [HIGH] 🔌 Connection failure ×172 in 6 files (first at python-producer.log line 1, 2026-11-05 16:28:22)
   [HIGH] ⚙️ Invalid client configuration ×1 in python-producer.log (first at line 34)
   [HIGH] ⌛ Records not delivered in time ×5 in 2 files (first at python-producer.log line 27)
   [HIGH] 🗺️ Topic not found in the metadata ×2 in 2 files (first at rust-producer.log line 1)
   [MEDIUM] 📥 Producer buffer full ×1 in synthetic-crashes/python-logging.log (first at line 2, 2026-11-05 16:30:02)
```

[🧰 Its report](reports/logs-clients/kafka_clients-log-report.html).

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
✏️ opens it in your editor). Open [🔥 the support bundle report](reports/logs/support_bundle-log-report.html) next to this table:

| Section | What it answers |
| --- | --- |
| verdict, quick links and tiles | the one-line diagnosis, a link to each section of the report (also a 🧭 Sections panel on the left of a wide screen, and a ⬆️ Top button once scrolled down), then one row of tiles: 🕐 the period covered (orange under 10 min), files and size read, 🏷️ the CP version (green ✅ when supported, amber ⏳ when support ends within 6 months or ⚠️ Platinum only, red ⛔ past end of support with a banner at the top of the report; 🏷️ CP Community for a `-ccs` version, with the Community end of support; from the supported versions table of the docs), ☕ the JDK of the components (`jvm.spec` of a Connect worker, `java.version=`, a GC log, a thread dump; with `--from-containers`, `java -version` of each container), 📡 the Apache Kafka Java client and librdkafka versions of the logs with their support, 🛟 the connector versions below the minimum supported on the CP release of their worker (supported-connector-version page of the docs, also on each 🔌 card), distinct records, occurrences (by level on the same tile), 🔴 Critical / 🟠 High / 🟡 Medium / 🟢 Low findings (a click keeps only those cards of 🔎 Findings), and the ☸️ tiles of a CFK bundle; a click on a tile opens its section (🕰️ log coverage, 🗂️ files, 🌳 root causes, 📈 occurrences over time, the ☸️ cards of 🔎 Findings) |
| ⚠️ not fully read | which inputs could not be read completely (truncated `.gz`, archive not extracted): the findings only cover the rest |
| 🧵 🔬 JVM dumps of the input | right after the verdict: the findings of the thread dumps of the input (severity, the CPU each thread used between the dumps, 🌐 a link to the full thread report), and the heap dumps with the `playground analyze heap-dump` command to run (📋 copy). Section 3 |
| 🔁 comparison | with `--compare`: what is new, gone, growing or shrinking (section 6) |
| 🎚️ filter bar | levels, components, connector, search, period: everything below follows it, and the URL keeps it. Click a connector name anywhere in the report to pick it (again: all the connectors) |
| 🔎 findings | the known causes with what to do and their exception chains, then the most frequent errors no known cause explains; each card says how much of it is in the current selection |
| 📥 data to request | what to ask the customer for next, with why and how: a complete copy of a file not fully read, a longer window (under 10 min), the logs since the last restart of a Connect worker or broker whose startup is not in the input (its config and plugin versions are missing), the configuration of the connectors whose class is unknown or only inferred (`curl -s "http://<worker>:8083/connectors?expand=info&expand=status"`) and the plugins installed when their version is unknown (`curl -s http://<worker>:8083/connector-plugins`), both read by the next analysis, the broker or Schema Registry logs when the findings point there (not for a database login failure), and a heap dump, GC logs, thread dumps or the certificates (the chain the server sends, the truststore) for the known causes they explain (unless 🧰 found them in the input). Never logs at DEBUG. A numbered card per request, 📋 copies each command. Also in the summary for a ticket |
| 🩹 known bugs fixed in a later version | an error of the logs that matches a bug of the connector plugin fixed in a later version (`tools/report-common/fixed_bugs.py`: from the changelog and the pull request of the fix), with a verdict from the version each connector runs: ⛔ affected (upgrade to the first fixed version of its line), ✅ it runs a version with the fix (another cause, or a regression), ❔ the logs do not give its version. Also on the 🔌 card of the connector and in the summary for a ticket |
| 🗓️ incident timeline | *what happened first?*: all files merged, the first occurrence of each error and known cause, restarts, connectors reconfigured, config changed between restarts, ✕ processes stopped (`shutting down`, `SHUTTING_DOWN`, `Kafka Connect stopping`), active controller changes, 🚪 the members of a consumer group removed by the group coordinator (the first 20), the 20 longest GC pauses of 1 s or more (from the GC logs of the input, unified or legacy format), 🐢 the bursts of broker signals (one row per burst of a kind on a broker: `📉 30 ISR shrinks on broker 1 in 37 min 55 s (orders-4, orders-8, payments-3 +1)`, events less than 5 min apart; from 1 ISR shrink or log cleaner failure, 3 of the others) and 🧵 each thread dump of the input (its time is the one the JVM printed, without time zone). With a CFK support bundle, its ☸️ cluster changes too: a pod terminated or restarted (✕, its reason: `OOMKilled`, `Error exitCode=1`), a custom resource edited and a StatefulSet rollout (changes for 🔗). 💥 under one of them: the ERROR / WARN of every file in the next 60 s, when they are 3 times the usual rate of the logs (5 at least), by known cause or exception. A chart above the table places them in time, one lane per component (the long gaps cut ⫽, hover a mark for its time and Δ, click it for its row, 🔍 drag over it to zoom, double-click or ⟲ All to zoom out, ⤢ to make that period the one of the whole report), and the Δ column gives the time since the previous event (the biggest gaps in bold) |
| 🔄 restarts and rebalances | from the INFO lines (the digest only keeps ERROR / WARN): the rebalances of the worker groups, the rejoins of the consumer groups with their reason, the connectors and tasks started, the workers and brokers (re)started and stopped, the active controller changes, the GC pauses of 1 s or more, 🚪 the members of a consumer group removed by the group coordinator of a broker (`has failed, removing it from the group`: session timeout; `removed dynamic members who haven't joined`: rebalance timeout, one line per round, which a grep of the first message misses; `on pending sync request expiration`: joined but did not sync), each counted with its rate per hour (logs that cover less than an hour: the count over the period they cover, `10 in 5 min`, rather than an extrapolated rate). 🌀 **storm**: 10 or more at 6 or more per hour (a consumer that leaves on purpose, `pro-actively leaving the group`, is not one, counted over the whole file: the short-lived consumers an Oracle CDC connector opens per table every 30 s or so, the schema history consumer of Debezium; their groups come last); also on the 🔌 cards and in the 🗓️ timeline. 🔁 **restart loop**: a worker that failed to start 3 times or more (`ERROR Failed to start Connect`, its rotated files merged), or a worker / broker stopped 4 times or more every 30 min or less: a red banner at the top of the section (`🔁 Restart loop: Kafka Connect (connect.log) failed to start 20 times, … a new attempt every ~5 min 40 s`), a badge on its rows, a line in the terminal summary and a sentence in the verdict, because a low rate per hour over a long bundle hides it. A chart shows them over time (drag to zoom) and each row has a swimlane of its occurrences on the period of the table; a click on a row shows it alone in the chart, zoomed on its period, and lists its occurrences under it, each with a link to its line in the log file (the first 100 noted). A connector picked in the filter keeps its rows, the worker group rebalances and process starts (every connector of the worker) stay |
| 🐢 broker signals | in the same table and chart as 🔄, and their own block in the terminal and the summary for a ticket: the signals of a broker under pressure, read from INFO / WARN lines that the digest of the errors misses: 📉 ISR shrinks and 📈 expands (`[Partition orders-0 broker=1] Shrinking ISR from 1,2,3 to 1,3`), 🪝 followers failing to fetch (`[ReplicaFetcher replicaId=3, leaderId=2, fetcherId=0] Error sending fetch request`, `Error in response for fetch request`, by the leader they fetch from; not the same line of a consumer, `[Consumer clientId=…]`, logged on every broker restart), ⏱️ requests timed out (`Disconnecting from node 2 due to request timeout`, by the broker that did not answer), 🧽 the log cleaner that died or skipped a partition (also the 🧽 Log cleaner stopped known cause), 🚦 requests throttled by a quota (librdkafka `THROTTLE`, `ThrottlingQuotaExceededException`), 📭 responses to clients already gone (`no open connection, connection id`). One row per kind and broker (a line without broker id: its file), with the partitions or peers they happen to most; 🌀 storm as the rebalances. 📥 then asks for the JMX metrics of the brokers (request handler and network idle ratio, request queue, produce / fetch latency, ISR shrinks) |
| 🗺️ cluster layout | from the `kafka-topics --describe` / `kafka-log-dirs` outputs of the input (section 3): the findings, a row per broker (replicas, leaders, disk, log dirs) and the lists of offline, under-replicated, under min ISR and non-preferred-leader partitions, biggest partitions and topics |
| 🧰 other files of the input | the GC logs, thread dumps, heap dumps, flight recordings, network captures and XStream reports of the input, with the command of the analyzer to run on each (section 3) |
| 🖥️ tasks by worker | with the logs of several workers: which worker ran each task and when (the `Starting task` lines that the worker running it logs, whatever the rebalance protocol; the rotated files of a worker are one worker, named by their folder), the errors of the connector in each worker's logs, and 🎯 a connector whose errors (3 or more) all come from one worker while its tasks ran on another one at the same time without error (its logs covering that time: errors before the tasks moved, an incident that ended, say nothing of the host): that host differs (DNS, truststore, plugin path, network, worker config). Also on the 🔌 card; follows the connector filter |
| 🔌 connectors | a card per connector with the icon of its type (the ones of the website, from its class or the database of its JDBC URL, else 🗄️ of its SQL dialect `Initializing writer using SQL dialect: SqlServerDatabaseDialect` or of its driver exception `SQLServerException`, `PSQLException`, `ORA-…`), ✅ the connectors without an error or a warning too (started, plugin version or config logged), its class: from `Instantiated connector … with version` (with the version), from a config, else 🔎 inferred from the loggers of the lines of its tasks when the logs miss its startup (`io.confluent.connect.hdfs3.TopicPartitionWriter`: Hdfs3SinkConnector, no version so no changelog nor support check; the package of the plugin when no class is known, else at least a sink or a source: `WorkerSinkTask` / `AbstractWorkerSourceTask` lines, `where consumed record is` of the errors reported by the runtime, its `connector-consumer-` / `connector-producer-` clients; and 💡 a hint from its name only, never used as its class: the words of its name, `hdfs3`, `elasticsearch`, `mysql`…, and the class of the connectors with the same name prefix), the 30 with the most errors first (show the others): errors, task kills, known causes, configuration, keys changed; ▶ only this connector keeps its card only (⤺ for all of them), the search filters the cards |
| 📈 occurrences over time | drag to zoom down to the second; an error repeated all day is spread over the day (sampled, counted with its weight) |
| 🌳 all root causes | every distinct error, by deepest exception (without one, by message: the same message with other numbers, `{…}` offset maps or `(A\|B\|C)` table lists is one root cause), linked to the finding that explains it |
| 🗂️ files and 🕰️ log coverage | per file and per folder of rotated logs, with the hours a folder has no log |
| 📄 records of each file | every distinct record, its exception chain colored, 📄 / ✏️ to the line |
| ⚙️ configuration | the configs logged at startup (one block per config class, the keys that differ between dumps, the keys changed between restarts) and the `.properties` / connector JSON of the input |
| 📤 Share | a card per action: the `.zip` of the report and its pages, 💬 the summary to paste, **🎫 Copy for a ticket** (Markdown, always sanitized), the same **🧵 for Slack** (bold, links, a bullet per row: Slack has no tables) and **📝 as rich text** (HTML with real tables, pastes formatted in Zendesk, Gmail, Confluence, Google Docs), 🔗 the path, ✉️ an email, the sanitization state first |

### The filters, the search, and links to a view

- **Levels** (`💀 FATAL`, `🔴 ERROR`, `🟠 WARN`), **components** (`🔌 Connect`, `🗄️ Kafka`, `📡 Clients`…, from the file
  names: `server.log` → Kafka), **connector** (the `[connector|task-0]` context of the line) and **period** (drag over
  📈) combine; the charts, root causes, files, records and timeline follow.
- **🕐 Period**, a row of the filter bar, as the time picker of Grafana: **⏱ Quick ranges** relative to the **end of
  the logs** (not to now: `Last 15 min of the logs`, `First 1 h of the logs`) and the times of the analysis (`± 5 min
  around the first ERROR`, `the peak`, `± 5 min around the first <known cause>`), **from → to** (📅 opens the date and time picker of the browser, or type them, or paste
  `2026-10-14 09:02 → 09:08` in from; `HH:MM` alone is the last day of the logs with that time), **Around** a time
  the customer gives (`09:05`, `± 5 min`), **⊖** zoom out, **◀ ▶** half a period earlier / later (keys `t ←`,
  `t →`, `t z`), ⤺ whole period, and the recent periods. **⏱️** on a row of the 🗓️ incident timeline: ± 2 min
  around that event. The period may go past the last record (the chart stops there; the records and 🔎 Search every
  log line use the whole period).
- **Search**: words that must all be there, `-word` to exclude, `"a phrase"`, `/regex/`. The matches are highlighted.
  `ora- -xout` keeps the Oracle errors that do not mention the outbound server; `/ORA-0101[0-9]/` the login errors.
  It searches the ERROR / WARN records; **🔎 Every log line** next to it searches the same text in every line.
- **🔎 Search every log line**, a section of its own, as OpenSearch Discover: **every line of every file**, INFO and
  DEBUG included (a `client.id`, `Revoking previously assigned partitions`, a `startTimeMs` that no ERROR has),
  searched in the browser, offline: the lines are written next to the report (`<report>-files/search/`, compressed,
  in the 📤 Share `.zip`). Same syntax plus fields: `level:INFO` (`level:ERROR,FATAL`, `-level:DEBUG`),
  `file:connect-0` (part of the path), `comp:connect`. It follows the 🕐 period and the component chips, and says how many lines match outside them and in which
  files (a thread dump taken hours after the logs is outside the period of the logs), with 🔎 search them too; a histogram
  of the matches over time (drag over it, or click a bar: the period of the report), the counts per level and per
  file (a click adds it to the query), the lines sorted by time with their file:line (📄 to the page of the file),
  and a click on a line shows the 8 lines around it. A budget bounds the lines written:
  `PLAYGROUND_LOG_SEARCH_MAX_MB` (200 MB of lines by default, the files with findings first; `0` turns it off); the
  files left out are listed. Not written with `--sanitize` (the lines are raw).
- **🔗 Link to this view** copies the URL, which holds the filters:
  `…/support_bundle-log-report.html#pg:comp=connect&q=ora-&t=1791972240-1791972360` opens the report on the Connect
  files, the Oracle errors, between 10:04 and 10:06 (`&lq=<query>`: 🔎 Search every log line runs it too).
- The component you pick is remembered for the next reports; a link wins over it.

> [!NOTE]
> The 🔎 findings are never rewritten by a filter: they are the diagnosis of the bundle. Each one says how much of it is
> in the selection (`▸ 340 of 1200 occurrence(s) here`), and the ones with nothing in it are hidden, with a
> `🙈 5 finding(s) with nothing in this selection hidden` **show them** to bring them back.

> [!WARNING]
> The connector of a record is the **connector context** of the Connect log line (`[orders-sink|task-0]`, the MDC
> `%X{connector.context}` of the log4j pattern of the workers), or a `WorkerSinkTask{id=orders-sink-0}` in its text.
> When the Connect logs have lines of tasks (`Instantiated task`, `Creating task`, `WorkerSinkTask{id=…}`, the
> connector configs) but no context at all, the pattern was changed: the report says so (`⚠️ No connector context
> (MDC) in the Connect logs of connect-0.log…`, under the verdict, in the summary, `.summary.connect_without_mdc` of
> `--json`) and 📥 Data to request gives the fix, `%X{connector.context}` back in the pattern (`connect-log4j2.yaml`
> on CP 8, `connect-log4j.properties` before, `spec.configOverrides.log4j` with CFK). Until then most records of the
> tasks count as "no connector context" in the 🔌 cards and the Connector filter.

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
- **Large inputs**: from 20 MB (an archive counts for its content: a 5 MB `.zip` of 250 MB of logs is large), a progress bar in the terminal and, in an interactive terminal, the report opens right
  away as a progress page (the phase, the file being read or the digests done when they run in parallel, the whole input, speed, ETA) that becomes the report. 2.4 GB of JSON
  lines take about 30 s.
- **Many files**: their digests run in parallel, 4 at a time (`PLAYGROUND_LOG_PARALLELISM`, `1` for one at a time with
  the progress bar of each file), merged in the order of the input: the same output, 40 files of 9 MB in 14 s instead
  of 31 s.
- **🏎️ mawk**: the digest of each file is an awk program, and it runs with `mawk` when it is installed (the default awk
  of Debian / Ubuntu, `brew install mawk` on macOS). On macOS it reads 2.5x faster than the awk of the system, with the
  same records: 1 GB in 48 s instead of 2 min, a CFK bundle of 837 MB in 33 s instead of 51 s. With 100 MB or more read
  by the awk of macOS, the summary ends with `🏎️ brew install mawk: …`. `PLAYGROUND_AWK` forces another one (`awk`:
  the awk of `PATH`); gawk is never picked, it is 2x slower than the awk of macOS there.
- **CFK support bundles** found inside the input are analyzed by the CFK analyzer, 4 at a time
  (`PLAYGROUND_CFK_PARALLELISM`), and linked from the log report in a ☸️ section: one browser tab.
- **Copies** of a file or of a bundle (an archive next to its extracted folder) are analyzed once.

---

### 🧵 Thread dumps, 🐢 broker signals, 🗺️ cluster layout

Two samples show them: `jvm_dumps` (the Connect log of section 2 with 3 thread dumps of a JVM and a heap dump, from the
samples of the thread and heap analyzers) and `broker_pressure` (the logs of 3 brokers while broker 3 falls behind,
with their `kafka-topics --describe` and `kafka-log-dirs` outputs).

```bash
playground analyze logs --sample jvm_dumps
```

The summary starts with the dumps (the verdict of the report also says `🧵 thread dumps: 4 critical / high finding(s),
Deadlock between deadlock-1, deadlock-2 (+3). 🔬 1 heap dump(s): run playground analyze heap-dump`):

```text
      [CRITICAL] Deadlock between deadlock-1, deadlock-2 (dump 1): each one waits for a lock held by the next. These threads will never progress; only a restart frees them. Fix the lock ordering in the code shown below (the top frames of each thread).
      [HIGH] Thread "cpu-burner" used 99.7% of a CPU between the dumps (RUNNABLE, in TdLoad.lambda$main$4(TdLoad.java:20)).
      [MEDIUM] Thread pool "pool-#-thread-#" grows across the dumps (14 -> 24 -> 34): threads are created and never stopped (executor not shut down, client not closed).
      🔥 CPU between the dumps: cpu-burner 99.7%
   🔬 1 heap dump(s) in the input, not analyzed here (Eclipse MAT in Docker, about as much memory as the dump): run
```

```bash
playground analyze logs --sample broker_pressure
```

```text
🐢 Broker signals (INFO / WARN lines: ISR changes, fetch errors, request timeouts, log cleaner, quotas)
   log cleaner (broker-2/server.log): 1 log cleaner failures, 1/h · thread died · 2026-11-09 14:50:00
   🌀 STORM broker 1: 30 ISR shrinks, 30.3/h · orders-4 ×10, orders-8 ×10, payments-3 ×7 (+1 more) · 2026-11-09 14:21:25 → 14:59:20
   🌀 STORM broker 2: 10 followers failing to fetch from it, 10.1/h · follower 3 ×10 · 2026-11-09 14:20:32 → 14:55:45
   broker 1: 6 requests timed out (no answer in request.timeout.ms), 6.1/h · ReplicaFetcher ×6 · 2026-11-09 14:25:30 → 14:55:00
   👉 a broker that falls behind: check its request handler / network idle ratio, disk latency, GC pauses and the network between brokers (playground broker metrics on a repro; the JMX metrics from the customer)
🗺️ Cluster layout (kafka-log-dirs.txt, kafka-topics-describe.txt): 4 topic(s), 31 partition(s)
   broker 1: 29 replica(s), 11 leader(s), 💽 18.4 GB
   broker 2: 29 replica(s), 4 leader(s) (6 of its preferred ones led elsewhere), 💽 7.0 GB
   broker 3: 29 replica(s), 16 leader(s), 💽 6.6 GB
   [HIGH] broker 3: log dir /var/lib/kafka/data2 has an error (org.apache.kafka.common.errors.KafkaStorageException): offline, its partitions moved to other dirs or went offline
   [MEDIUM] 3 under-replicated partition(s) of 31: orders-0, orders-4, orders-8
   [MEDIUM] broker 2: 6 of the 10 partitions it is the preferred leader of are led by another broker (60% > 10% leader.imbalance.per.broker.percentage): a preferred leader election moves them back
   [MEDIUM] Disk usage skew: broker 1 uses 18.4 GB, broker 3 6.6 GB (average 10.7 GB): one broker fills first; rebalance the replicas
```

and on the timeline, one row per burst: `📉 30 ISR shrinks on broker 1 in 37 min 55 s (orders-4, orders-8, payments-3 +1)`.
CPU and memory use are not in logs: the 📥 data to request asks for the JMX metrics of the brokers and the CPU, disk
and network of their hosts (`playground broker metrics` gives the same metrics on a reproduction).

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
written in the logs, and with the epoch times of the librdkafka lines (`%3|1793896102.923|FAIL|…`) as UTC. A file where
no time is found (another format of time, no time at all) is analyzed whole rather than dropped, with a warning:

```text
⏱️ client.log: no time found in its lines (YYYY-MM-DD hh:mm:ss, librdkafka epoch), --since / --until not applied: the whole file is analyzed
```

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
are listed in the summary (`🔁 changed between restarts`) and in the ⚙️ section of the report. Only a real restart counts
(a `started` / `stopping` line, or the start config of the component, `DistributedConfig`, `KafkaConfig`,
`SchemaRegistryConfig`…, dumped again 30 s or more later): two dumps of the same class in one run are two instances (two
telemetry exporters of a broker, the readiness check of the image then the worker, the key and value converters), not a
change. The config of a connector itself is compared without a restart: a reconfiguration does not restart the worker.

---

## 6. Did the fix work? `--compare`

```bash
playground analyze logs -f <after> --compare <before>
playground analyze logs --sample compare_fix          # the log of a worker the day after a fix, against the day before
```

`<before>` is a file, a folder, an archive (analyzed again with the same `--connector`, `--with-worker`,
`--errors-only`, `--include-harmless`, `--include-warnings`, `--ocr`, `--sanitize`, but not `--since` / `--until`: it
covers another period), or a JSON written by `--json` earlier. A run of it whose CFK part failed keeps its log analysis:

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
compared **per hour** and the rates are shown (`1 → 7 (6.67/h → 0.3/h)`). The [🔁 comparison report](reports/logs-compare/compare_fix-log-report.html)
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
| `.known_causes[]` | title, severity, occurrences, first occurrence, advice, exception chains of the killed tasks, knowledge-base articles (`kb_articles`) |
| `.root_causes[]` | every distinct error, its connectors, `explained_by` |
| `.timeline[]` | the incident timeline |
| `.connectors[]` | the card of each connector |
| `.comparison` | with `--compare` |
| `.fixed_bugs[]` | title, ref, plugin, fixed_in, occurrences, first, and `connectors[]` with version, verdict (`affected`, `fixed`, `unknown`) and `upgrade_to` |
| `.data_to_request[]` | what, why, how |
| `.task_workers` | `workers[]`, `start` / `end` (period of the swimlanes), `tasks[]` (task, connector, `runs[]`: worker, from, to, starts) and `connectors[]` (`workers[]` with task starts, errors, warnings; `only_on` and `clean_overlap[]`: worker, task, from, to of the runs elsewhere during the errors) |
| `.other_files` | `files[]` (label, kind, path, kept) and `commands[]` of the 🧰 files for another analyzer |
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
Oracle `user/password@`), PEM blocks, cookies, IPs (v4 and v6), hostnames, emails, LDAP DNs and the host and realm of
Kerberos principals (`kafka/<HOST-1>@<REALM-1>`); the same placeholder
for a value everywhere (`<HOST-1>` in the digest, the report and the JSON), also on both sides of `--compare`. Best
effort: review before sharing.

What holds the raw lines is **not written** with `--sanitize`, so it is not in the 📦 `.zip` of the report either: the
file pages (a location of the report is then plain text), 🔎 the search of every line and the full 🧵 thread reports
(the summary of the thread dumps in the report is sanitized, and gives the `playground analyze thread-dump` command).

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
| a connector that fails on one worker only (a cluster of workers) | `playground analyze logs -f <the logs of every worker>`: 🎯 in 🖥️ Tasks by worker names the worker its errors come from |
| a worker with hundreds of connectors, one is failing | `playground analyze logs -f <bundle> --connector <name>`, or ▶ only this connector on its 🔌 card |
| did the fix work? the logs before and after it (two workers, two days) | `playground analyze logs -f <after> --compare <before>` (two CFK support bundles: the bundles and their pod logs are compared) |
| a CloudWatch, OpenSearch, Kibana, Splunk, Datadog or Loki export | `playground analyze logs -f <export.json\|.csv>`: converted back to log lines, oldest first |
| logs pasted in a Word document, or exported to Excel | `playground analyze logs -f <logs.docx\|export.xlsx>` (also `.odt`, `.ods`): converted back to log lines (a paragraph a line; an Excel export of Kibana / Splunk / Datadog through its time, level, message columns, its dates converted), the pictures of the document listed in 🧰 Other files of the input |
| logs sent as screenshots (also pasted in a Word document) | `--ocr`: read by OCR, the Vision framework of macOS (offline, compiled once into `~/.cache/playground`), else `tesseract`, else tesseract in a container built on first use; digested as `<picture> (📷 OCR)`, with the brackets of the timestamps, the `{id=…}` of a task, the tab of the frames and the lines wrapped by the terminal rebuilt, and the usual misreadings of a package name fixed (`orq.apache`), never a digit: the report says the records are approximate (📷 Read by OCR). Without `--ocr`, listed in 🧰 Other files of the input with the command. A Claude Code session reads pictures more accurately (`/kdp-case`) |
| a PDF, an old `.doc` / `.xls` | not analyzed: listed in 🧰 Other files of the input with what to do (`pdftotext` for a PDF, save as `.docx` / `.xlsx`) |
| the logs of a Python, Go, .NET, JavaScript, C/C++ or Rust application | `playground analyze logs -f <the logs>`; to reproduce, `other/client-<language>` runs that client against the playground |
| a Kafka Streams application that rebalances in a loop or stops | `playground analyze logs -f <the logs of every instance>`: the 🌊 Kafka Streams section |
| thread dumps or a heap dump in the same zip as the logs | `playground analyze logs -f <bundle>`: the thread dumps are analyzed in 🧵 🔬 JVM dumps of the input (full thread report next to the report), the heap dump command is at the top: run it |
| GC logs, a flight recording or a pcap in the same zip as the logs | `playground analyze logs -f <bundle>`, then run the commands of 🧰 Other files of the input (they point at the copies kept in `<input>-other-files/`) |
| a slow or overloaded cluster (ISR shrinks, high latency, under-replicated partitions) | `playground analyze logs -f <the broker logs + kafka-topics --describe + kafka-log-dirs outputs>`: 🐢 broker signals (storms by broker and partition, on the timeline), 🗺️ cluster layout (leader skew, disk skew, offline log dirs); then ask for the JMX metrics of 📥 |
| what to ask the customer for next | `playground analyze logs -f <bundle>`: 📥 Data to request (also in `<input>-ticket.md`); for a CFK bundle, its own 📥 section |
| "the logs are clean" | check 🕐 the period covered and ⚠️ not fully read, then the 🔭 overview of what the logs contain and what to ask for |
| point engineering at one burst | filter the report (connector, level, drag over the burst), 🔗 Link to this view, 📤 Share the `.zip` |
| only the incident, in a day of logs | `playground analyze logs -f <bundle> --since "2026-11-06 10:00" --until "2026-11-06 11:00"` (the line numbers stay those of the files) |
| "is it fixed in a newer version?" | `playground analyze logs -f <bundle>`: 🩹 when the error is a known bug of the plugin, the verdict for the version each connector runs; otherwise the 📋 changelog command of its 🔌 card, with `--grep <exception>` |
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
playground analyze logs --sample connect_task_failure|support_bundle|broker_pressure|jvm_dumps|kafka_streams|kafka_clients|compare_fix
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

### Without the playground

`analyze logs` reads files only: it needs neither Docker nor the rest of the playground. A colleague, a customer or a
partner can run it from a shallow clone of three folders (about 33 MB, a few seconds):

```bash
git clone --depth 1 --filter=blob:none --sparse https://github.com/vdesabou/kafka-docker-playground.git
cd kafka-docker-playground && git sparse-checkout set scripts tools cfk-analysis
./scripts/cli/playground analyze logs -f <file|folder|.zip|.tar.gz> --sanitize
```

| Needs | Why |
| --- | --- |
| bash 4.2 or later | the CLI (macOS ships bash 3.2: `brew install bash`) |
| python3 3.8 or later (standard library only) | the report, the summary, the exports of log consoles, the sanitizer |
| jq | the configs of the input, `--sanitize`, `--compare`, `--json` |
| awk (mawk when installed, the fastest; else gawk, busybox or macOS awk), gzip, tar | the digest, the archives |
| optional: unzip | a `.zip` (without it, python3 extracts it) |
| optional: zip | the 📤 Share `.zip` of the report |
| optional: Docker, or PyYAML (`pip install PyYAML`) | the ☸️ sections of a CFK support bundle (without either, its pod logs are still in the report) |

Checked on Ubuntu 24.04 and 20.04 (Python 3.8, mawk), RHEL UBI 9 and Alpine (busybox), without Docker. On Windows: WSL.
`analyze gc-logs`, `analyze thread-dump` and `analyze oracle-xstream-report` on files work the same way.

With nothing installed but Docker (a customer, Windows without WSL, a locked-down laptop): the
[`kdp-analyze-logs` image](deep-dive-analyze-logs.md?id=🐳-with-nothing-installed-but-docker).

