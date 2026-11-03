# 🧭 Which command do I need?

The `playground` CLI has a command for most support questions: digests of logs and customer bundles, connector
diagnostics, JVM and network analyzers, version and changelog lookups, reproduction models. This page maps the
**question you have** to the **command that answers it in one call**, and the raw `docker` / `curl` / `kafka-*`
command it replaces.

You don't have to read it: ask the CLI.

```bash
playground find-command "why is my connector not working"
playground find-command "customer support bundle cfk"
playground find-command "which version fixes this CVE" --limit 3
playground find-command "kafka-consumer-groups reset offsets" --json
```

`playground find-command` searches the tables of this page, the "Recipes for support repros" table of every
[deep dive](deep-dives.md) and the help of every command, and prints the best matches first, with the deep dive to
read next.

> [!TIP]
> This page is also what Claude Code reads (skill `kdp-commands`) to pick a command. When you add a command that answers
> a new question, add a row here: the first column is what someone would type, in their own words.

## 🥇 Questions answered in one call

These answer the most common questions in one bounded, non-interactive call. They are worth trying **before**
grepping the repository or reading raw logs: they keep tens of thousands of log lines and dozens of grep hits out of
sight.

| Question | Command | Instead of |
| --- | --- | --- |
| "is there an example that does X?" | `playground find-example "oracle cdc ssl"` (`--category ccloud`, `--limit 5`, `--json`) | `grep -ril` over `connect/`, `ccloud/`, `reproduction-models/`… |
| "what did I run, with which flags, did it pass? replay it" | `playground history --list [<words>]` (result, date, duration, branch, number of runs; `--json`, `--last`, `--run`, `--stats`) | `tail playground-run-history` |
| "what is running right now?" | `playground status` (lists containers, flags exited/restarting ones) | `docker ps`, reading `playground.ini` |
| "what is the state of the connectors?" | `playground connector status` | curl on the Connect REST API |
| "is the cluster healthy? (a broker down, under-replicated / under min ISR / offline partitions, KRaft quorum)" | `playground broker health` (exit 1 when not healthy, `--wait-healthy --max-wait 120`, `--json`); `playground broker describe` for brokers, controller, `metadata.version` | `kafka-topics --under-replicated-partitions`, `kafka-metadata-quorum` |
| "why is this connector not working?" | `playground connector diagnose [--connector <c>]` (status + error digest + lag/offsets + next steps, HTML report in `/tmp/playground-diagnose`, `--no-open`) | `status`, `container logs --errors`, `show-lag`, `offsets get` one by one |
| "why does one task do all the work? which worker / partitions / tables does each task get? which topics does it use?" | `playground connector tasks [--connector <c>]` (state, worker, the config keys that differ per task, partitions of each sink task, `--all-keys`, `--json`) / `playground connector topics` (active topics, `--reset`); `playground connector restart --only-failed` restarts only what is FAILED | `curl .../connectors/<c>/tasks`, `kafka-consumer-groups --describe` + matching client ids by hand |
| "what is in the dead letter queue, and why?" | `playground topic dlq inspect [--topic <dlq> \| --connector <c>]` (records grouped by exception / root cause / original offsets, `--grep`, `--json`, HTML report); then `playground topic dlq replay` (`--to <t>`, `--dry-run`) once fixed | `topic consume` on the DLQ + reading `__connect.errors.*` headers by hand |
| "what changes in the connector config when the customer upgrades the plugin from X to Y? since which version does key K exist?" | `playground connector-plugin config-diff -c confluentinc/<name> --from X [--to Y] [--file <their config>]` (keys ➕ / ➖ / default ✏️, `--json`) / `playground connector-plugin config-key -k K -c <class> --since-version` (no environment, Docker) | `show-config-parameters` on two running versions, reading release notes |
| "is this connector config valid? what differs from the customer's?" | `playground connector validate` (config on stdin, or `--connector <c>` for the running one) / `playground connector diff --connector <c> --file cfg.json` (`--with-connector`, `--defaults`, side-by-side HTML report with the doc of each key) | `curl .../config/validate`, comparing JSON by eye |
| "the customer sent a CFK Connector / Strimzi KafkaConnector resource, a terraform `confluent_connector`, a `connect-standalone` `.properties`, a `curl /connectors?expand=info` dump" | `playground connector create-or-update -c <c> <file>` / `connector validate < <file>` / `connector diff -c <c> --file <file>` read them directly (detected; `create-or-update` adapts the bootstrap servers, schema registry, license, replication factors to the playground, `--no-adapt`); `playground connector convert <file> [--to heredoc\|json\|cfk\|strimzi\|terraform\|properties]` for the repro heredoc (values to fill in as variables, `--secrets-as-variables`) or to answer in the customer format; **`playground repro bootstrap --config <file> -d "<case> <symptom>" --no-run`** builds the whole repro model from it (example picked from the class, behaviour from the customer, systems and secrets from the example) | converting YAML / HCL / properties to JSON by hand |
| "why did it fail?" | `playground container logs -c connect --errors` (`--since 10m`, `--include-warnings`) | `docker logs connect`, scrolling raw logs |
| "when did it fail? how many times did it restart? what changed in the config before?" | `playground connector history [--connector <c>]` (timeline from the `connect-status` / `connect-configs` topics: states per task with worker and trace, config diffs, pause / resume / delete, summary; `--since 12h`, `--json`, works for deleted connectors) | `kafka-console-consumer` on `connect-status` + diffing JSON by hand |
| "show me recent raw lines" | `playground container logs -c connect --no-follow --tail 500` / `--grep "Caused by" --no-follow` | `docker logs connect \| tail` |
| "what is failing in these logs?" (customer bundle, CI artifact) | `playground analyze logs -f <file\|folder\|.zip\|.tar.gz>` (ends with a 🧭 summary: known causes + what to do, root causes, per-connector counts, config logged and its changes between restarts; `--connector <c>` to keep one connector, `--show-config <c>` for its config, `--include-warnings`, `--max-findings 10`, `--json --json-sections summary,findings,root_causes`, `--sample connect_task_failure` to try it; a CFK support bundle inside is detected, see below) | `unzip` + `grep ERROR`, ad-hoc `python3` |
| "why is the connector stuck / hanging / burning CPU?" | `playground analyze thread-dump -c connect` (live, 3 dumps 5s apart) / `-f <dump file\|folder>` (repeat `-f` for several dumps of one JVM) | `jstack` + reading raw thread dumps |
| "is the connector making progress? how many records were skipped / retried / sent to the DLQ? is Debezium lagging?" | `playground connector metrics [--connector <c>]` (JMX task metrics per task + the MBeans of the connector itself, Debezium lag / queue / snapshot, findings and next step, `--watch 10s`, `--json`; Telemetry API for fully managed) | `get-jmx-metrics -c connect --domain kafka.connect` and reading hundreds of raw MBeans |
| "long GC pauses, memory leak?" | `playground analyze gc-logs -c connect` / `-f <gc log\|folder>` | reading raw GC logs |
| "what fills the heap? memory leak, `OutOfMemoryError: Java heap space`?" | `playground analyze heap-dump -f <.hprof\|.hprof.gz>` (digest in `<output-dir>/summary.txt`, HTML report with Kafka-aware hints, `--json`) | Eclipse MAT by hand |
| "where does the time of the connector tasks go? (I/O, Kafka, locks, converters, hot methods)" | `playground analyze flight-recorder -c connect --duration 60s [--connector <c>]` (live, over JMX; `--trace-method <Class::method>` adds every call of a method with its duration and caller, JDK 25+) / `-f <file.jfr>` (`--sample jdbc_postgres_sink` to try it, `--json`); for an open-ended window in a script, `playground debug flight-recorder --action start` … `--action stop` (copies and analyzes the `.jfr`, `--no-analyze`) | `jcmd JFR.start` + JDK Mission Control by hand |
| "what goes over the wire? refused / reset connections, TLS alerts, Kafka or HTTP errors (with the bodies)" (live, or a customer's `.pcap`) | `playground debug tcp-dump -c <c> [--port <p>] [--filter <bpf>] --duration 30s` (several `-c` at once, `--action start` … `--action stop`; analyzed at the end) / `playground analyze tcp-dump -f <.pcap\|.pcapng>` (`--kafka-port`, `--http-port`, `--sample kafka_and_network_errors\|http_errors`, `--json`) | `tcpdump` in the container + reading Wireshark by hand |
| "what does this method receive / return / throw? which calls are slow? which record makes it fail?" (live, no restart, no debugger) | `playground debug jscissors -c connect --class <class\|regex> [--method <m\|regex>] --duration 60s` (or `--action start` … `--action stop`; `--operation VALUES\|RETURN_VALUE\|STACK\|EXCEPTION_THREADS…`, `--only-failed`, `--slower-than 500ms`, `--config-file`, `--restart` to trace the startup) / `playground analyze jscissors -f <trace folder>` (`--sample filestream_sink_bad_json`, `--json`) | remote debugging, adding log lines and rebuilding the connector |
| "what is wrong in this CFK support bundle?" | `playground analyze logs -f <dir\|.tar.gz\|.zip>`: the bundle is detected and analyzed as a whole, pods, CRs, events, versions, recent changes and logs (`--problem "<component, symptom, since when>"` ranks the issues that explain the customer's problem first with a 🎯 verdict, a 📥 Data to request section says what to ask the customer for next; `--component connect`, `--severity high`, `--json` with `"type": "cfk-bundle"`, `--logs-only` for the plain digest, `--sample cfk_bundle` to try it) | `tar x` + grepping pod logs and CR yamls |
| "what does this Oracle XStream diagnostics report say?" (`orclcdc_diag_<date>.html`) | `playground analyze oracle-xstream-report -f <report.html> -p "<symptom, since when>"` (repeat `-f` to compare reports, `-c oracle` on a running example, `--sample synthetic_failures` to try it, `--json`); skill `kdp-xstream-report` for the write-up, `docs/deep-dive-oracle-cdc.md` for the mental model | reading the HTML report section by section |
| "is this example red in CI too, and why?" | `playground get-ci-result --test <dir> --logs` (`--environment cfk`, `--podman`, HTML report in `/tmp/playground-ci-result`); `--json` for the status alone (`ok`, `fail`… exit 1 when red) | reading the 🔥 issue, `gh run view --log` (it truncates long jobs) |
| "how fast is this connector? is version Y slower?" | `playground connector benchmark [--connector <c>]` (`--mode steady`, `--connector-tag A --connector-tag B`, `--json`); skill `kdp-benchmark` for load scripts, shapes, fully managed | `sleep` + counting records by hand |
| "will this schema be accepted? what changed between v1 and v3, which compatibility rule refuses it?" | `playground schema check-compatibility --subject <s> < new.avsc` (exit 0 / 1, nothing registered, `--compatibility <rule>`) / `playground schema diff --subject <s> [--from N] [--to M\|@file]` (field-level ➕ ➖ ✏️ with hints + the registry's verdict for BACKWARD / FORWARD / FULL, Avro / JSON Schema / Protobuf, `--json`) | registering to see if it fails, comparing schemas by eye |
| "who deleted the schema, when, soft or hard? when was the compatibility rule changed? which subjects use schema id N?" | `playground schema history [--subject <s>] [--since 2d]` (timeline from `_schemas`: ⏺️ / 🧟 / 💀 with the ids that stop resolving, 🛡️ rule changes; `-f <dump>` for a customer's `kafka-console-consumer --property print.key=true --property print.timestamp=true` dump, `--json`) / `playground schema describe --subject <s>` (rule and mode with their source, versions, references, referenced by, shared ids, strategy → topic) / `--id <id>` | `kafka-console-consumer` on `_schemas` + reading JSON by hand |
| "the customer sent their schemas (a `curl /schemas` dump, a `_schemas` topic dump, a registry export): load them with the same ids" | `playground schema import -f <file\|folder> [--dry-run]` (IMPORT mode, ids and versions kept, `--on-conflict skip\|overwrite\|merge`, `--new-ids`) / `playground schema export -o <folder>` (manifest + one file per version, to ship in a repro model) | registering each schema by hand, ids that don't match the records |
| "the producer fails with `Rule failed: …` (data contract), do these records pass the rules of the subject?" | `playground schema register --subject <s> --rule '<name>:<CEL expr>'` (or `--rule-set @rules.json`; warns when the registry drops them: needs the `RuleSetResourceExtension`) / `playground schema test-rules --subject <s> --record '<json>'` (the real serializer with `use.latest.version=true`: ✅ / ❌ rule + expression, exit 1 on a failure) | a Java producer written for the case |
| "Schema Linking: did the schemas reach DR? why do DR consumers get `Schema not found`?" | `playground schema exporter create --name <n> --cluster europe [--destination-context <c>]` (mdc-plaintext + the replication lab override for the exporter extension; `--destination-url` elsewhere) / `exporter list\|status` / `playground schema compare --from europe --to us --to-context .<c>` (exit 1 when different) / `--context <c>` on the schema commands, `playground schema contexts` | `curl` on `/exporters`, `/contexts/.<c>/subjects` by hand |
| "this schema was accepted before the upgrade and is refused now: which CP version refuses it, and why?" | `playground schema validate --cp-version <old> --cp-version <new> < schema.avsc` (a throwaway Schema Registry of each version next to the running broker, ✅ / ❌ with the error per version, `--schema` repeatable for v1 then v2, `--json`) | upgrading the environment to try |
| "what does this transform chain (SMT) do to a record? why does it fail?" | `playground connector smt test --connector <c> [--record <json> \| --from-topic <t> --offset N]` (or the transforms on stdin; `--cp-version A --cp-version B` to compare CP versions, `--smt-plugin owner/name:version` / `--smt-jar` for SMTs not in the worker, `--json`; HTML report in `/tmp/playground-smt-test/`) | a FileStream sink + TRACE logs of `TransformationChain` |
| "is this bug fixed after version X? what changed between X and Y? which CVEs?" | `playground connector-plugin changelog --connector-plugin confluentinc/<name> --from X [--to Y] [--grep "symptom\|CVE"]` (release notes from the docs.confluent.io changelog feeds, self-managed Confluent plugins only, `--json`); with a repro model ending with `playground repro assert`, **`playground repro bisect --from X --to Y`** runs it on the versions in between (binary search, one `playground run` per version: stops the running environment) and prints the changelog where the verdict changes | opening the docs changelog page, Glean for "fixed in" |
| "is this Kafka / Schema Registry / ksqlDB / REST Proxy bug fixed after CP X? which patch bumped Netty?" | `playground cp-changelog --from X [--to Y] [--component schema-registry] [--grep "symptom" \| --security]` (commit titles from the docs.confluent.io CP changelog feeds, 7.4+, community components only: no Confluent Server / Control Center, no CVE ids; `--json`) | Glean for "fixed in", reading the CP release notes page |
| "what is this connector plugin? license, latest version, how far behind is the customer's, which examples use it (CI), fully managed equivalents?" | `playground connector-plugin info -c confluentinc/<name> [--from <theirs>]` (`--json`) | Hub page + `find-example` + `versions` one by one |
| "which jackson / netty / driver version ships in plugin version X? which plugin version upgrades it? what changed between X and Y?" | `playground connector-plugin dependencies -c confluentinc/<name> --connector-tag X [--connector-tag Y] [--grep jackson]` / `--find-first <artifact>:<version>` (`--json`) | downloading the plugin and listing `lib/` by hand |
| "the customer's scanner reports CVEs in connector version X: which are real in the jars, which version fixes them?" | `playground connector-plugin cve-scan -c confluentinc/<name> --connector-tag X [--compare-with Y]` (grype in Docker, fixed CVE ids matched with the release notes, `--severity high`, `--json`, HTML report in `/tmp/playground-cve-scan`; a scanner result, not an official statement) | running a scanner on a downloaded zip by hand |
| "fully managed connector: which connector version does cc-connect image V ship? which image first has the fix of version X? what changed lately?" (Confluent only) | `playground connector-plugin fm-versions -c confluentinc/<Type> [--cc-connect-version V \| --find-first X \| --last 50 --with-log]` (`--json`) | reading `cache-versions.env` tag by tag in cc-docker-connect |
| "where is the source code of connector X (version Y)? which commits / files changed between X and Y?" | `playground connector-plugin sourcecode --connector-plugin confluentinc/<name> [--connector-tag Y] --only-show-url` (`--grep <regex>` greps the code of that version); with 2 `--connector-tag`: `--log [--grep <symptom>]` / `--files [--path <glob>]` (`--json`) | guessing repo / branch, GitHub code search, reading the compare page |
| "which CFK operator code logs this error? is it fixed after version X?" (Confluent only, private repository) | `playground debug cfk sourcecode --bundle <bundle> --grep "<message>" [--compare-with 3.3.0]` (or `--cfk-version` / `--operator-tag`; clones the tag once in `/tmp/cfk-operator-sourcecode/`, folder on the last line, `--only-show-url`) | GitHub code search (default branch only, misses templated messages) |

### Good to know

- `playground find-example` searches connector class, script path, README title and script body of every
  runnable example — including the private `reproduction-models/` submodule — and prints the
  ready-to-paste `playground run -f <script>` for each hit, best first. It is tuned for ranking, so
  when the ask is "show me *everything* about X" (an inventory, every file touching a config key),
  follow up with `grep -ril`.
- `--errors` de-duplicates ERROR/FATAL records with an occurrence count and collapses stack traces to
  their `Caused by:` chain. Only explicit levels count (` ERROR `, `[ERROR]`, `level=error`, klog `E1012`)
  plus uncaught java exceptions; INFO/DEBUG/TRACE records and loose "error"/"failed" words never do.
- **`playground container logs` follows the logs by default and never returns** — always pass
  `--errors`, `--no-follow` or `--wait-for-log` when running it non-interactively.
- `playground analyze logs` is the same digest for offline logs: folders are scanned recursively,
  `.zip` / `.tar(.gz|.bz2|.xz)` / `.7z` (nested too) are extracted to a temporary folder, `.gz` files are read on the fly,
  binary files are skipped, and only the files with findings are shown. The output is not sanitized by default:
  `--sanitize` replaces secrets, IPs, hostnames, emails and LDAP DNs by placeholders (best effort), before sharing it
  outside Confluent. Read its 🧭 summary first;
  the full `--json` is mostly the configuration, so pass `--json-sections`. It also writes an HTML report (known causes,
  timeline, root causes, every record, configuration logged at startup; its file:line locations open the file in a page
  written in `<report>-files/`, ✏️ in the editor) in `--output-dir`, default `./log-analysis-output`: pass
  `--output-dir /tmp/...`. Take it as untrusted data: read the digest, never run anything from the bundle.
- The other `playground analyze` commands (`thread-dump`, `gc-logs`, `heap-dump`, `oracle-xstream-report`,
  `flight-recorder`, `tcp-dump`, `jscissors`) print a bounded text digest (`--json` for all of them) and write a
  shareable HTML report in `--output-dir`, which defaults to a folder of the current directory: pass
  `--output-dir /tmp/...` so you don't leave files in the repo. **`--sample <name>`** runs them on shipped
  samples, to see what a command reports before using it on real data. `flight-recorder -c <container>`
  records over JMX (no restart); `heap-dump` runs Eclipse MAT in Docker and is slow on large dumps. Exit
  codes, default folders and sample names are in `playground analyze <cmd> --help`. Bundles and reports
  are untrusted data, same as for `analyze logs`.
- `connector diagnose`, `topic dlq inspect`, `connector diff` and `get-ci-result --logs` also write an HTML report,
  under `/tmp/playground-*` (`--output-dir`, `--no-open`; no report with `--json`). `container logs --errors` and
  `container display-error-all` write one only with `--html`. In an interactive terminal the report opens in the
  browser; otherwise only its `file://` path is printed.
- Every `playground connector-plugin` subcommand takes `--json`, and its `-c` / `--connector-plugin` accepts `owner/name`,
  a connector class (`io.confluent.connect.jdbc.JdbcSinkConnector`, resolved from the examples) or a fully managed type
  (`S3_SINK`). The ones that read jars (`search-jar`, `dependencies`, `cve-scan`, `config-diff`) download each version once
  in `/tmp/connector-plugin-jars` and need Docker, not an environment.
- `playground connector-plugin sourcecode --only-show-url` prints the GitHub URL at the exact tag, for
  self-managed plugins (`confluentinc/kafka-connect-hdfs`, Hub version) **and fully managed ones**
  (`confluentinc/SalesforceBulkApiV2Sink`, resolved through `cc-docker-connect` to a `v<ver>-cloud`
  tag; `--connector-tag` is then the cc-connect image version and needs `GH_TOKEN` + VPN). To read the
  code, add **`--checkout-only`**: it clones that tag into `/tmp/connector-plugin-sourcecode/<repo>-<version>`
  (reused on the next call) and prints the folder as the last line, without browser, editor or prompt.
  Don't pass `--open` or `--compile` non-interactively: they open an editor.
- `playground connector benchmark` needs a load: sinks replay the example's `topic produce`, sources run its
  `benchmark-load.bash`. Before writing or editing a load script, benchmarking a fully managed connector or
  comparing versions, read the `kdp-benchmark` skill (`.claude/skills/kdp-benchmark/SKILL.md`).
- To understand one example, read its `.sh` and `ls` its folder (compose overrides, sibling variants).

## 🥈 Use the `playground` CLI, not raw `docker` / `curl` / `kafka-*`

Before typing `docker`, `curl` on a REST API or a `kafka-*` shell command, in an example script, in a reproduction
model or to inspect a running environment, check this table. The CLI wraps them with the right container names,
ports, credentials (plaintext vs SASL vs mTLS vs ccloud), retries and `playground.ini` state, so the `playground` form
keeps working across environments where the raw command only works on `plaintext`.

| Instead of | Use |
| --- | --- |
| `docker compose up/down`, `docker compose -f ...` | `playground start-environment` / `playground stop` |
| `docker ps`, checking what runs | `playground status` |
| `docker logs <c>`, `docker logs -f <c> \| grep X` | `playground container logs -c <c>` (`--errors`, `--no-follow --tail N`, `--since 10m`, `--grep X --no-follow`, `--wait-for-log "X" --max-wait 120`, `--open`) |
| `docker exec <c> <cmd>` | `playground container exec -c <c> --command "<cmd>"` (`--root`, `--shell`) |
| `docker restart <c>`, `docker kill $(docker ps -q)` | `playground container restart\|recreate\|kill\|kill-all -c <c>` |
| `docker cp` | `playground container cp` |
| reading a `.properties` inside a container | `playground container get-properties -c <c>` |
| grepping docs / `config-*.txt` / examples for a connector config key (doc, default, since when, values used) | `playground connector-plugin config-key --key <k> [--connector-class <class or FM type>]` (offline) |
| `curl localhost:8083/connectors/...` | `playground connector status\|show-config\|logs\|pause\|resume\|restart\|delete\|update` |
| `curl .../connectors/<c>/offsets` | `playground connector offsets get\|alter\|reset` |
| `kafka-consumer-groups --describe` for a connector | `playground connector show-lag` |
| `kafka-consumer-groups --describe\|--reset-offsets\|--delete` for any other group | `playground consumer-group describe\|reset-offsets\|delete --group <g>` (`--to-earliest`, `--to-datetime`, `--shift-by`…, `--dry-run`) |
| `sleep N` waiting for a connector to start, or for a source connector to produce | nothing: `playground connector create-or-update` waits for a self-managed connector to be RUNNING by default (strict in examples, warn-only in repro models; `--wait` strict everywhere and for fully managed, `--no-wait` to skip). Otherwise `playground connector wait --connector <c>` (`--state RUNNING\|PAUSED\|STOPPED\|FAILED`, `--max-wait 120`) / `playground topic wait-for-records --topic <t> --min-expected-messages N --max-wait 120` |
| `kafka-console-producer`, `kafka-avro-console-producer`, a transactional Java producer | `playground topic produce -t <t> --nb-messages N` (+ schema on stdin; `--transactional-id <id> --transaction commit\|abort\|open` for records in one transaction) |
| `kafka-console-consumer` | `playground topic consume --topic <t> --min-expected-messages N --timeout 60` |
| `kafka-configs --entity-type users\|clients` (client quotas) | `playground quota get\|set\|delete` (`--user`, `--client-id`, `--connector <c>` for its tasks, `--all-users`, `--all-client-ids`, `get --json`) |
| `kafka-configs --entity-type brokers` (dynamic broker configs) | `playground broker config get\|set\|delete` (`--key <k>`, `--value <v>`, `--broker <id>`, cluster-wide without it; `get --key <k>` shows the value and its source, or the key it comes from when not set, `--all` every config, `--json`) |
| `docker stop broker2`, restarting the brokers one by one | `playground broker stop --broker <id>` (`--kill` for a crash) / `playground broker start --broker <id>` (waits for a healthy cluster) / `playground broker rolling-restart` (`--brokers 3,2,1`, waits for a healthy cluster between brokers); needs `--enable-multiple-brokers`, not on cfk |
| `kafka-transactions` (open or hanging transactions, a `read_committed` consumer stuck) | `playground broker transactions list\|describe\|describe-producers\|find-hanging\|abort` (`describe-producers --topic <t>` shows the start offset of each open transaction) |
| `kafka-metadata-quorum`, `kafka-features`, `kafka-broker-api-versions` | `playground broker describe` (`--api-versions --broker <id>`) |
| `get-jmx-metrics -c broker` to check broker load | `playground broker metrics` (one column per broker: idle ratios, p99, bytes in/out, `--topic <t>`, `--json`) |
| `kafka-reassign-partitions`, `kafka-leader-election` | `playground topic reassign` (`--replicas 2,3`, `--brokers 1,2,3`, `--throttle`, `--no-wait` / `--verify-only`) / `playground topic elect-leader` (`--leader <broker>` for a controlled leader move, `--unclean`); needs `--enable-multiple-brokers` |
| `kafka-topics --create\|--list\|--delete\|--describe` | `playground topic create\|list\|delete\|describe` |
| comparing a topic with its replica by hand (`GetOffsetShell` on both clusters) | `playground topic compare --topic <t> --from europe --to us` (`--to-topic`, `--wait`, `--json`; two topics of one cluster outside mdc) |
| `docker exec broker-us kafka-…`, `curl localhost:8283/connectors` in an `mdc-*` environment (two clusters) | `playground topic\|consumer-group\|connector\|schema\|broker\|quota … --cluster us\|europe` (or `export PLAYGROUND_CLUSTER=us`) |
| `GetOffsetShell` / counting records | `playground topic get-number-records --topic <t>` |
| `kafka-console-consumer` on `__consumer_offsets` | `playground topic display-consumer-offsets` |
| `curl localhost:8081/subjects/...` | `playground schema list\|get\|register\|get-compatibility\|set-compatibility\|delete` (`--json`, `get --schema-only`, `--global` for the registry-wide rule, `delete --dry-run`) |
| `jstack`, `jmap`, `jcmd`, `tcpdump`, JFR, a java agent | `playground debug thread-dump\|heap-dump\|tcp-dump\|flight-recorder\|jscissors`, then `playground analyze thread-dump\|heap-dump\|gc-logs\|flight-recorder\|tcp-dump\|jscissors` |
| `tc` / `iptables` in a container to slow down or cut its network (`add_latency`…) | `playground debug degrade-traffic` (`--latency`, `--jitter`, `--loss`, `--corruption`, `--rate`, `--action start\|stop\|status`) / `playground debug block-traffic` |
| editing `log4j.properties` to raise a log level | `playground debug log-level set --package <pkg> --level TRACE` |
| `docker exec sql-client bin/sql-client.sh`, `curl` on the Flink jobmanager REST API (`:18081/jobs`) | `playground flink sql` (statements on stdin or `--file`) / `playground flink list-jobs` (`--state`, `--json`) / `playground flink cancel` (`--job`, `--all`) |
| `docker exec -i ksqldb-cli ksql http://ksqldb-server:8088 << EOF`, `curl` on the ksqlDB REST API (`:8088/ksql`), `sleep N` waiting for a `CREATE … AS SELECT` | `playground ksqldb sql` (statements on stdin or `--file`, exit 1 on a failed statement, `--ignore-errors` when expected, `--query-timeout`) / `playground ksqldb wait [--source <s>]` (persistent queries RUNNING with no lag) / `playground ksqldb list` / `playground ksqldb describe --source <s>` (queries, lag, statistics, errors, `--json`) |

Legitimate exceptions — use the raw command only for these, and only when no flag above covers it:

- `docker inspect` / `docker image ls` to assert **which image** a container runs (e.g. community vs
  enterprise connect image) — there is no CLI equivalent.
- `curl` against a **test HTTP endpoint that is part of the example** (`httpserver:9006/set-response-error-code`,
  a mock API, a cloud provider emulator) — that is the example's payload, not a Kafka component.
- one-off shell inside a container for something with no CLI equivalent (`ls` a plugin directory) — even
  then prefer `playground container exec`.

