# 🍪 Deep dive: `playground container logs` and `playground analyze logs`

The two commands that read logs for you. `container logs` reads the logs of a running container (or CFK pod): raw,
filtered, waited for, or summarized into a digest of ERROR/FATAL records. `analyze logs` gives the same digest for
logs that don't come from a running container: a customer support bundle, a CI artifact, a log file you were sent.
Takes about 15 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session [🕵️ A connector failed: read the logs, live or from a customer bundle](/sessions?id=🕵️-a-connector-failed-read-the-logs-live-or-from-a-customer-bundle) shows it in 3 minutes: the `--errors` digest of a failed sink, `--grep`, `--wait-for-log`, and `analyze logs` on a customer bundle.
>
> The video session [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose)
> uses `container logs --errors` to see what a connector does when the network breaks. This page goes further: how
> the digest works, the traps of following, a hands-on lab and recipes for support repros.

| You want | Flags |
| --- | --- |
| what went wrong, in a few lines | `-c connect --errors` (`--since 10m`, `--include-warnings`, `--max-findings N`) |
| the last raw lines, and get the prompt back | `-c connect --no-follow --tail 500` |
| only the lines matching a pattern | `-c connect --grep "Caused by" --no-follow` |
| to watch live | `-c connect` (ctrl-c to stop), several `-c` for several containers |
| to block until a line shows up (scripts) | `-c connect --wait-for-log "<text>" --max-wait 120` |
| the whole log in your editor | `-c connect --open` |
| the digest of files, folders, `.zip` / `.tar.gz` bundles | `playground analyze logs -f <path>` (repeat `-f`) |

---

## 1. Mental model (the 3 things to remember)

1. **`container logs` follows by default, and never returns.** Without `--no-follow`, `--errors` or
   `--wait-for-log`, it runs `docker container logs -f` and waits for new lines until ctrl-c. That's what you want in a
   terminal, and what hangs a script, a CI job or an AI agent. **`--since 10m` and `--grep X` alone still follow.**
   Only three flags return on their own:

   | Flag | Returns when |
   | --- | --- |
   | `--no-follow` | the bounded log is printed (default `--tail 200`) |
   | `--errors` | the digest is printed (it never follows) |
   | `--wait-for-log "<text>"` | the text is found, or `--max-wait` is exceeded (exit 1) |

2. **The digest only trusts explicit levels, and groups records by message and root cause.** A record counts when its
   first line carries an explicit level: an uppercase token (` ERROR `, `[ERROR]`, `"ERROR"`), a logfmt / JSON field
   (`level=error`, `"level":"error"`) or a klog prefix (`E1012 …`), plus uncaught Java exceptions on level-less lines
   (`Exception in thread …`, `java.lang.IllegalStateException: …`). INFO/DEBUG/TRACE records that mention "error",
   and level-less lines with "failed", never count. Then:
   - the stack trace is collapsed to its **chain** (first exception line + every `Caused by:`) and **3 frames of the
     deepest cause**;
   - records with the same message and the same deepest cause are **one finding**, whatever their timestamps and ids
     (digits are ignored in the comparison): `🔴 ERROR x24 (first seen line 1, last seen line 52)`;
   - FATAL first, then ERROR, then WARN (with `--include-warnings`), capped by `--max-findings` (default 40).

3. **It reads what the container printed, nothing else, and it never fails.** `container logs` is `docker container
   logs` (or `kubectl logs --all-containers` on CFK, through the pod name resolved for you: `connect` → `connect-0`):
   stdout and stderr of the container since it was created. Files a component writes inside the container are not
   in it. Both `--errors` and `analyze logs` **exit 0 even with findings**: they are a reading aid, not an assertion.
   To fail a script on a log line, use `--wait-for-log`.

---

## 2. Reading live logs

```bash
# follow (ctrl-c): the last 200 lines, then new ones
playground container logs -c connect

# several containers at once: followed in parallel, each line prefixed with [connect] / [broker]
playground container logs -c connect -c broker

# bounded, then the prompt back
playground container logs -c connect --no-follow --tail 500
playground container logs -c connect --no-follow --since 10m          # --since alone would follow
playground container logs -c connect --grep "Caused by" --no-follow   # whole log scanned

# the whole log in your editor (saved to /tmp/<container>-<date>.log)
playground container logs -c connect --open

# CFK: the logs of the previous instance of a restarted pod
playground container logs -c connect --previous
```

Gotchas:

- **Default window**: `--tail 200`, except with `--since`, `--errors`, or `--grep` + `--no-follow`, where the whole log
  is read. `--tail all` reads everything explicitly.
- `--since` takes a duration (`10m`, `1h`) or a timestamp (`2026-09-24T16:00:00`), as `docker logs --since`.
- `--grep` is a plain `grep` pattern (basic regular expression: `.` and `[` are special), applied line by line: you
  get the matching lines, not the stack trace around them. For the stack trace, use `--errors` or `--open`.
- `playground container restart` keeps the log; `container recreate` (and `playground stop`) creates a new container,
  and the previous log is gone (Docker keeps logs per container). Save it first with `--no-follow --tail all > file` or
  `--open`.
- **Timestamps are the container's, in UTC**: `[2026-10-23 10:44:36,598]` in the connect log is 12:44 on a host at
  UTC+2. `--since 10m` is converted for you, but compare raw timestamps with care.
- `--previous` only exists for CFK pods: with Docker it's ignored with a warning.
- `playground connector logs` is a shortcut for `container logs -c connect` for self-managed connectors.

---

## 3. The ERROR digest: `--errors`

```bash
playground container logs -c connect --errors
playground container logs -c connect --errors --since 10m                         # only the recent records
playground container logs -c connect --errors --include-warnings --max-findings 10
playground container logs -c connect -c broker -c schema-registry --errors        # one digest per container
playground container logs -c connect -c broker --errors --html                    # + an HTML report of the digests
playground container display-error-all --html                                     # every container, + an HTML report
```

What a finding looks like (from the shipped sample, see section 4):

```text
🔎 6 distinct record(s), 6 occurrence(s), in 5278 lines

🔴 ERROR x1 (first seen line 5251, last seen line 5251)
[2026-10-14 10:05:55,629] ERROR [cdc-xstream-oracle-source|task-0] WorkerSourceTask{id=cdc-xstream-oracle-source-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted:
    org.apache.kafka.connect.errors.ConnectException: An exception occurred in the change event producer. This connector will be stopped.
    Caused by: org.apache.kafka.connect.errors.ConnectException: The capture process 'CAP$_XOUT_1' is in an 'ABORTED' status. …
        at io.confluent.connect.oracle.xstream.cdc.streaming.OracleStreamingChangeEventSource.checkCaptureProcessState(OracleStreamingChangeEventSource.java:546)
        at io.confluent.connect.oracle.xstream.cdc.streaming.OracleStreamingChangeEventSource.execute(OracleStreamingChangeEventSource.java:147)
```

How to read it:

- **`xN`** is the number of occurrences; **first / last seen line** are line numbers in the log that was read (with
  `--since`, counted from the start of that window). A finding seen once at startup and a finding repeating until the
  last line are two very different stories.
- **Read the last `Caused by:`** first: it's the root cause. The frames shown are those of that deepest cause, which
  is usually where the connector code is.
- No finding: `✅ no ERROR/FATAL record found in 12523 lines`. With `--since`, that means nothing *recently*: widen it
  before concluding.

Gotchas:

- A message whose varying part is not a number (a topic name, a file name) gives one finding per variant.
- A record longer than 400 lines is cut into several records; each line is shortened to 300 characters in the digest.
- `--errors` conflicts with `--grep` and `--wait-for-log`, and needs nothing else: it never follows.
- A digest printed in a log (a CI log containing `container logs --errors` output) is not counted twice: its headers
  are recognized and skipped.
- `--html` (with `--errors`, and on `display-error-all`) writes the same HTML report as `analyze logs`, one card per
  container, to `/tmp/playground-log-reports/`, and opens it from a terminal. It's opt-in, because these commands are
  run all the time. `get-ci-result --logs` writes one for the failing scripts of a CI job too (see
  [run and versions](/deep-dive-run-and-versions.md)).

---

## 4. Offline: `playground analyze logs`

```bash
playground analyze logs -f connect.log
playground analyze logs -f ./customer-logs.zip --include-warnings
playground analyze logs -f ./logs -f broker.log.gz --max-findings 10

# try it on the shipped samples
playground analyze logs --sample connect_task_failure     # a Connect worker log (Oracle XStream task failure)
playground analyze logs --sample support_bundle           # a .zip with that log and a gzipped broker log
playground analyze logs --sample cfk_bundle               # a CFK support bundle (see below)
playground analyze logs --sample cfk_kraft_migration      # a CFK support bundle with a stuck ZooKeeper to KRaft migration
playground analyze logs --sample cfk_rollout              # a CFK support bundle with a half-done CP upgrade
playground analyze logs --sample cfk_rollout --sample cfk_rollout_after   # two bundles of that cluster, compared
```

What it does with what you give it:

| Input | Handling |
| --- | --- |
| a folder | scanned recursively, sorted, `__MACOSX/` and `.DS_Store` ignored |
| `.zip`, `.tar`, `.tar.gz`, `.tgz` | extracted to a temporary folder (deleted at the end), nested archives too |
| `.gz` | decompressed on the fly |
| a CFK support bundle (a folder with `cluster-details.txt`, or `cluster-resources/` + `operator/`), alone or inside a folder or an archive | analyzed as a whole by the CFK analyzer (Docker): pods, custom resources, events, versions, recent changes and its logs, sanitized, in its own HTML report. See [the CFK deep dive](deep-dive-cfk.md). `--logs-only` gives the plain digest instead |
| a `.properties` file, a JSON file with connector configs | analyzed like a text file, and shown in the ⚙️ configuration section of the HTML report |
| any other file | analyzed when it's text, **skipped when binary** (counted in the last line) |
| a copy of a file or of a CFK support bundle already analyzed (an archive next to its extracted folder) | skipped (`⏭️ … same content as …` / `⏭️ … same CFK support bundle as …`, only one report), counted in the last line |

🔒 The digest, the HTML report and the JSON are **sanitized by default**:
- **What is replaced:** passwords and other secrets (`password=…`, JAAS configs, tokens, API keys, credentials in
  URLs, PEM blocks), IPs, hostnames, emails and LDAP DNs.
- **Placeholders:** `<REDACTED>`, `<IP-1>`, `<HOST-1>`… A value gets the same placeholder everywhere in one run.
  Values the application already masked (`password=********`) are left as they are.
- **Report:** the last log line says what was redacted (`redaction_summary` in the JSON).
- **Best effort:** review before sharing. `--no-sanitize` keeps the values, for internal logs only.

The output names each file with its path inside the archive, and only shows files with findings:

```text
🔥 ERROR/FATAL digest for …/support-bundle.zip:bundle/broker/server.log.gz
🔎 1 distinct record(s), 24 occurrence(s), in 54 lines

🟠 WARN x24 (first seen line 1, last seen line 52)
[2026-10-14 09:59:12,446] WARN No client metrics available in request, skipping export (io.confluent.telemetry.emitter.ClientMetricsTelemetryExporter)

🔥 ERROR/FATAL digest for …/support-bundle.zip:bundle/connect/connect.log
🔎 12 distinct record(s), 19 occurrence(s), in 5278 lines
…
✂️ 9 more distinct record(s) not shown, increase --max-findings

📊 2 file(s) with findings out of 2 scanned (binary files skipped: 0)
✅ HTML report saved: /home/me/log-analysis-output/support_bundle-log-report.html
```

### 🧭 The summary, `--connector`, `--show-config`

After the digest of each file, a short **summary** gives what the HTML report says first, across all the files:

```text
🧭 Summary: 6 occurrence(s) of 6 distinct record(s) in 1 file(s), 2026-10-14 10:03:58 → 2026-10-14 10:05:55
   🔌 by connector: cdc-xstream-oracle-source 1 · no connector context 5
🧠 Known causes
   [HIGH] 🧨 A connector task was killed ×1 in connect-oracle-xstream-task-failure.log (first at line 5251, 2026-10-14 10:05:55)
      → it stays FAILED until it is restarted: fix the cause (the exception chain of the record), then playground connector restart --connector <connector>
   [HIGH] 🔑 Authentication failure ×1 in connect-oracle-xstream-task-failure.log (first at line 9, 2026-10-14 10:03:58)
      → check the credentials (user, password, API key, keytab) of the client or of the external system
🌳 Root causes not explained by a known cause
   ERROR ×1 StreamsException: ORA-26804: Apply "XOUT" is disabled.
   …
⚙️ Configuration logged (24), the last dump of each: --show-config <connector|config class|client id> prints one
   🧩 cdc-xstream-oracle-source: SourceConnectorConfig ×3, EnrichedConnectorConfig ×3, AbstractConfig, …
   📡 Clients: AdminClientConfig, ConsumerConfig
```

| Flag | What it does |
| --- | --- |
| `--connector <name>` (`-c`, repeatable) | only the records and configs of that connector (`[name\|task-0]` / `[name\|worker]` context, `WorkerSinkTask{id=name-0}`), in the digest of each file, the summary, the HTML report and the JSON. The digest says how many records of the file it left out. `--with-worker` also keeps what has no connector context (worker, Kafka) |
| `--show-config <name>` | prints the configuration logged at startup as `key = value` (sanitized), the last dump of each, with the keys changed between restarts. For a **connector**: its own configs only (`EnrichedSourceConnectorConfig`, the connector's own class such as `AbstractConfig`, converters, `TaskConfig`); a config contained in a bigger one with the same values (`SourceConnectorConfig`, the `[name\|worker]` copy of a `[name\|task-0]` one) is only named, and its producer / consumer / admin clients are summed up in one line. For a **config class** (`ProducerConfig`, `DistributedConfig`…) or a **client id**: every match |
| `--json-sections summary,findings,root_causes` | with `--json`, only these sections (`summary`, `findings`, `known_causes`, `root_causes`, `files`, `files_without_findings`, `configuration`). The configuration is most of the JSON (one dump of 100 keys per client), so leave it out unless you need it |

**🔁 Changed between restarts**: when a config is logged again (a restart of the connector or the worker) with
another value for a key, the summary, `--show-config`, the HTML report and `.configuration[].changes` of `--json` list
it, for example `SinkConnectorConfig [my-sink|worker]: tasks.max 1 → 4 · first line 12 (2026-10-29 10:10:00)`.
That answers "did the customer change something before it broke?". Each dump lists every key of its config class,
defaults included, so only values that differ count. Two configs logged with the same identity (the key and the
value converter, two consumers with one `client.id`) would look like a value going back and forth: a change undone
within 60 s is ignored.

### 🌐 The HTML report, and `--json`

Besides the terminal digest, `analyze logs` writes a self-contained HTML report, `<first input>-log-report.html`, in
`--output-dir` (default `./log-analysis-output`). It opens in the browser when you run the command from a terminal.
It holds **every** distinct record, not only the first `--max-findings` of each file:

| Section | What it shows |
| --- | --- |
| verdict and tiles | files scanned and with findings, distinct records, FATAL / ERROR / WARN occurrences |
| 🔎 findings | well-known causes first (task killed, authentication, authorization, TLS, unknown magic byte, connection refused, `OutOfMemoryError`, class loading…), each with its earliest occurrence and what to do (for killed tasks: one line per distinct exception chain, with its `Caused by:`, count, connectors and first line, also in `.known_causes[].chains` of `--json`), then the most frequent root causes no known cause explains; chips above them filter by severity (same in every report with findings) |
| 📈 occurrences over time | ERROR/FATAL and WARN per time bucket, from the timestamps of the records |
| 🌳 root causes | records grouped by their deepest exception (or by message when they have none), with occurrences, files and connectors |
| 📄 one card per file | every distinct record, with its count, connector, first and last line and timestamp, and its exception chain; **📋 Show context** unfolds the raw lines around its first occurrence (2 before, the record with its full stack trace up to 30 lines, 2 after), with their line numbers (`▶` on the first line of the record), also in `.files[].records[].context` of `--json` |
| ⚙️ configuration | the configs the components log when they start (`KafkaConfig values:`, `DistributedConfig`, `SchemaRegistryConfig`, the config of each connector and of its tasks with their `[connector|task-0]` context, `ProducerConfig` of a client app…, defaults included, the last one of each class / context / `client.id`, 50 per file), and the config files of the input (`.properties`, connector JSON: a connector config, `{"name", "config"}` or the output of `/connectors?expand=info`), grouped by config files, components, connector and clients, with a key / value filter, also in `.configuration` of `--json`. Sanitized like the records |

A sticky bar above the root causes filters them and the records: FATAL / ERROR / WARN chips with several levels
(`--include-warnings`), and a **Connector** picker when the records carry the connector context of the Connect log
line (`ERROR [my-connector|task-0] …`, `[my-connector|task-0|offsets]`, `[my-connector|worker]`, `WorkerSinkTask{id=my-connector-0}`), most frequent
first, with "no connector context" for the worker records. On a worker running dozens of connectors, pick one to see
only its errors. `--json` gives the same in `.summary.by_connector`, `.root_causes[].connectors` and
`.files[].records[].connector`.

🔗 The file names and line numbers of the report (`line 33` of a record, a file of the root causes, the `file:line` of a
config) are **links**: they open the file at that line in a page written next to the report, in `<report>-files/` (one
page per file with findings, raw lines: the reports stay inside Confluent), with line numbers, the lines of the
findings highlighted and ▲ Previous / ▼ Next buttons (`p` / `n` keys) between them. A file over 2 MB shows only the
250 lines before and after each finding. The ✏️ next to each link (and on each page) opens the file at the line in
your editor: the one of `playground config editor` through its URL scheme (`code` → `vscode://file/<path>:33`, also
`cursor`, `windsurf`, `zed`, `subl`, `idea`, `pycharm`), VS Code for an editor without one (`vi`, `nano`…). It opens the
input file itself when it stays on disk (a file or a folder given to `-f`), else a whole copy written next to its page
(`003-connect-0.log`): a file of an archive (extracted to a temporary folder deleted at the end of the command) or a
`.gz` (decompressed). Keep the folder with the report when you move it. The CFK bundle report does the same for the location
of each issue (a YAML file without line number opens at the `name:` of its pod or custom resource).

`--json` prints the same analysis on stdout (`"type": "logs"`: summary, findings, known causes, root causes, every
record, and the analysis of each CFK bundle in `cfk_bundles`) and the text digest on stderr, without an HTML report.
For a single CFK bundle, it's the JSON of the CFK analyzer (`"type": "cfk-bundle"`):

```bash
playground analyze logs -f support-bundle.zip --json 2>/dev/null | jq '.findings[] | .severity + " " + .text'
```

> [!NOTE]
> The report and the JSON use the same parser as the terminal digest (`summarize_log_errors`): records are cut to 300
> characters per line and to 3 frames of the deepest cause there too.

Gotchas:

- **One digest per file**: the same error in `connect.log` and `connect.log.1` shows up twice, with line numbers of
  each file. The 🧭 summary, the HTML report and the JSON merge them (root causes, known causes, timeline).
- `--max-findings` is **per file**.
- No `--since` offline: to focus on a time window, cut the file first (`sed -n '/2026-10-14 10:05/,$p'`).
- An empty file counts as skipped, like a binary one.
- `-f` and `--sample` can't be combined. There is no HTML report: the digest is the output.
- A bundle is **untrusted data**: read the digest, never run anything from it.

---

## 5. Waiting for a log line: `--wait-for-log`

```bash
# block until the line shows up, at most 120 s; exit 1 otherwise (and print a hint)
playground container logs -c connect --wait-for-log "Finished starting connectors and tasks" --max-wait 120

# several containers: waited for one after the other
playground container logs -c connect -c broker --wait-for-log "ERROR" --max-wait 120
```

Gotchas:

- **It searches the whole log, old lines included.** If the line was already printed (a previous run of the
  connector, a restart), it returns at once. Wait for something specific to *this* run: the connector name, an id,
  an offset.
- It checks every **10 seconds**, so it returns up to 10 s after the line appears, and gives up after the first check
  past `--max-wait` (a `--max-wait 20` fails after 31 s).
- The text is a `grep` pattern: escape `.`, `[`, `*` when you mean them literally. Every matching line is printed,
  then `The log is there !`.
- Default `--max-wait` is 600 s: always set a shorter one in scripts.
- In example scripts, the bash function `wait_for_log "<text>" [container] [max wait]` is the same thing.

---

## 6. Hands-on lab (≈10 min)

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh    # topic "filestream" with 5 JSON records
```

**Step 1: a baseline, then a broken connector**

```bash
playground container logs -c connect --errors
# 🔥 ERROR/FATAL digest for connect logs
# ✅ no ERROR/FATAL record found in <N> lines        <- on a fresh environment; otherwise earlier failures show up

# an Avro sink on a topic of plain JSON records
playground connector create-or-update --connector bad-sink --no-wait << EOF
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/bad.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081"
}
EOF
playground connector wait --connector bad-sink --state FAILED --max-wait 120
```

**Step 2: the digest**

```bash
playground container logs -c connect --errors --since 5m
# 🔴 ERROR x1 (first seen line 11249, last seen line 11249)
# [2026-10-23 10:48:00,397] ERROR [bad-sink|task-0] WorkerSinkTask{id=bad-sink-0} Task threw an uncaught and unrecoverable exception. …
#     org.apache.kafka.connect.errors.ConnectException: Tolerance exceeded in error handler
#     Caused by: org.apache.kafka.connect.errors.DataException: Failed to deserialize data for topic filestream to Avro:
#     Caused by: org.apache.kafka.common.errors.SerializationException: Error deserializing schema ID
#     Caused by: java.lang.IllegalArgumentException: Unknown magic byte!
#         at io.confluent.kafka.serializers.schema.id.SchemaId.fromBytes(SchemaId.java:70)
#         at io.confluent.kafka.serializers.schema.id.DualSchemaIdDeserializer.deserialize(DualSchemaIdDeserializer.java:47)
playground connector restart --connector bad-sink
playground connector wait --connector bad-sink --state FAILED --max-wait 120
playground container logs -c connect --errors --since 5m
# 🔴 ERROR x2 (first seen line 10253, last seen line 11653)      <- same failure after the restart: one finding
```

**Step 3: grep, tail, and the follow trap**

```bash
playground container logs -c connect --grep "Unknown magic byte" --no-follow
# Caused by: java.lang.IllegalArgumentException: Unknown magic byte!     <- the matching lines only, no context
playground container logs -c connect --no-follow --tail 5
timeout 5 playground container logs -c connect --since 1m; echo "exit=$?"
# … the last minute of raw log, then nothing until timeout kills it …
# exit=124                                                       <- --since alone still follows
```

**Step 4: waiting**

```bash
playground container logs -c connect --wait-for-log "Unknown magic byte" --max-wait 30
# ⌛ Waiting up to 30 seconds for message Unknown magic byte to be present in connect container logs...
# Caused by: java.lang.IllegalArgumentException: Unknown magic byte!
# The log is there !                                <- in 0.5 s: the line was already in the log
playground container logs -c connect --wait-for-log "this line never shows up" --max-wait 20; echo "exit=$?"
# 🔥 The logs in connect container do not show 'this line never shows up' after 20 seconds. Please troubleshoot with …
# exit=1                                            <- after 31 s: one check every 10 s
```

**Step 5: the same digest, offline**

```bash
playground container logs -c connect --no-follow --tail all > /tmp/lab-connect.log 2>&1
gzip -kf /tmp/lab-connect.log
playground analyze logs -f /tmp/lab-connect.log.gz --output-dir /tmp/lab-log-reports
# 🔥 ERROR/FATAL digest for /tmp/lab-connect.log.gz
# 🔴 ERROR x2 … WorkerSinkTask{id=bad-sink-0} …      <- the same findings as the live digest
# 📊 1 file(s) with findings out of 1 scanned (binary files skipped: 0)
# ✅ HTML report saved: /tmp/lab-log-reports/lab-connect-log-report.html   <- 🧨 A connector task was killed, 🧲 Unknown magic byte
playground analyze logs -f /tmp/lab-connect.log.gz --json 2>/dev/null | jq -r '.known_causes[].title'
# 🧨 A connector task was killed
# 🧲 Unknown magic byte
# …
playground analyze logs -f /tmp/lab-connect.log.gz --json 2>/dev/null | jq -r '.known_causes[0].chains[] | "\(.occurrences) \(.connectors) \(.caused_by)"'
# 1 ["bad-sink"] IllegalArgumentException: Unknown magic byte!   <- what killed the task: one line per distinct exception chain
playground connector delete --connector bad-sink
```

```bash
playground stop
```

---

## 7. Recipes for support repros

| Situation | Command |
| --- | --- |
| a customer support bundle (`.zip`, `.tar.gz`, folders of rotated logs) | `playground analyze logs -f <bundle> --max-findings 15`, then `--include-warnings` if no ERROR explains it |
| a CI artifact or a log pasted in a ticket | save it to a file, `playground analyze logs -f <file>` |
| "the connector failed during the night" (still running env) | `container logs -c connect --errors`: look at `xN` and *last seen line*, then `--grep "<connector name>" --no-follow` around it |
| "is it the connector or the broker?" | `container logs -c connect -c broker --errors --since 30m` |
| a repro that must wait for a log line instead of `sleep` | `container logs -c connect --wait-for-log "<line specific to this run>" --max-wait 120` |
| a repro that must fail if an error appears | `--wait-for-log "<the error>" --max-wait 60` succeeds when it *does* appear: invert it in bash (`if playground container logs … ; then logerror …; exit 1; fi`) |
| the stack trace around one line | `container logs -c connect --open` (full log in the editor), or `--errors` for the collapsed chain |
| more than the stack trace | raise the level first: `playground debug log-level set --package <pkg> --level TRACE`, reproduce, then `--errors --since 5m` / `--grep` |
| share the log of a repro | `container logs -c connect --no-follow --tail all > connect.log` before `playground stop` |

In a repro model, the pattern is: trigger, wait for the effect, show the digest.

```bash
playground connector create-or-update --connector my-sink << EOF
{ … }
EOF
playground topic produce -t my-topic --nb-messages 10 --value '{"id": %g}'
playground connector wait --connector my-sink --state FAILED --max-wait 120
playground container logs -c connect --errors --since 5m
```

---

## 8. Cheat sheet

```bash
playground container logs -c <container> [-c <c2>] \
  [--errors [--since 10m] [--tail N|all] [--include-warnings] [--max-findings N] [--html]] \
  [--no-follow [--tail N|all] [--since 10m] [--grep <pattern>]] \
  [--wait-for-log "<text>" [--max-wait S]] [--open] [--previous]
playground analyze logs -f <file|folder|.zip|.tar.gz|.gz> [-f …] [--include-warnings] [--max-findings N] [--output-dir <dir>] [--json]
                       [--connector <name> [--with-worker]] [--show-config <name>] [--json-sections summary,findings]
                       [--no-sanitize] [--logs-only] [--component connect] [--severity high] # CFK support bundle
playground analyze logs --sample connect_task_failure|support_bundle
```

- Follows by default: in scripts, always `--errors`, `--no-follow` or `--wait-for-log`. `--since` / `--grep` alone follow.
- Digest = explicit levels only, chain + 3 frames of the deepest cause, one finding per message and root cause.
- `xN` + first / last seen line tell "once at startup" from "every minute until now".
- `--errors` and `analyze logs` exit 0: not assertions. `--wait-for-log` matches old lines too, every 10 s.
- Offline: one digest per file, archives extracted, `.gz` read on the fly, binaries skipped.
- Offline also writes an HTML report (known causes, timeline, root causes, every record, configuration) in `--output-dir`; `--json` for scripts.
  With several levels (`--include-warnings`), chips FATAL / ERROR / WARN above the root causes hide or show the records of a level;
  a Connector picker keeps the records of one connector (`[my-connector|task-0]` context of the line).
- Sources: [`container/logs.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/container/logs.sh),
  [`analyze/logs.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/analyze/logs.sh),
  `summarize_log_errors` in [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh),
  [`tools/log-analyzer/log_report.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/log-analyzer/log_report.py),
  `wait_for_log` in [`utils_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/utils_function.sh),
  samples in [`tools/log-analyzer/samples/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/tools/log-analyzer/samples).

---

**Links**

- 🎬 Video sessions: [🕵️ A connector failed: read the logs, live or from a customer bundle](/sessions?id=🕵️-a-connector-failed-read-the-logs-live-or-from-a-customer-bundle), [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose) (uses `--errors`)
- 📖 [Analyze what you collected](/reusables?id=🔎-analyze-what-you-collected) in the Reproduction toolkit
- 💡 [Tail container logs](/tips-and-tricks?id=tail-container-logs) in Tips & Tricks
- 🧠 CLI reference: [playground container logs](/playground%20container%20logs),
  [playground analyze logs](/playground%20analyze%20logs), [playground connector logs](/playground%20connector%20logs)
