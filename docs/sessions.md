# 🎬 Bite size sessions

Short sessions (2–4 minutes), each about one thing the playground does for you. The narration is typed in the terminal as
`#` comments, so you can pause the video and copy the commands. The sessions that write an HTML report end on it, and
link to a live report so you can click around it yourself.

> [!TIP]
> The shorter clips at the top of the [introduction](/introduction.md) (🍿 See it in action) show one command each. The
> sessions here explain what the output means and what to do next.
>
> To go further on a topic, the [🍪 Deep dives](/deep-dives.md) are the written companions of some sessions: how the
> commands work under the hood, their gotchas, a hands-on lab and recipes for support repros.

| | Session | Needs |
| --- | --- | --- |
| 🕹️ | [Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) | docker |
| 🩺 | [A sink is RUNNING but writes nothing: diagnose, dead letter queue, replay](/sessions?id=🩺-a-sink-is-running-but-writes-nothing) | a running example |
| 🔀 | [What does this transform chain (SMT) do to a record?](/sessions?id=🔀-what-does-this-transform-chain-do-to-a-record) | a running example |
| 🧑‍💻 | [The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version) | nothing |
| 🐞 | [A breakpoint in a running connector: remote debugging](/sessions?id=🐞-a-breakpoint-in-a-running-connector-remote-debugging) | a running example |
| 🧵 | [A connector looks stuck: analyze thread dumps](/sessions?id=🧵-a-connector-looks-stuck-analyze-thread-dumps) | nothing (`--sample`) |
| ♻️ | [Long GC pauses or a memory leak: analyze GC logs](/sessions?id=♻️-long-gc-pauses-or-a-memory-leak-analyze-gc-logs) | nothing (`--sample`) |
| 🛩️ | [A slow connector: where does the task time go?](/sessions?id=🛩️-a-slow-connector-where-does-the-task-time-go) | nothing (`--sample`) |
| 🅾️ | [Oracle XStream CDC lags or is idle: analyze the orclcdc_diag report](/sessions?id=🅾️-oracle-xstream-cdc-lags-or-is-idle) | nothing (`--sample`) |
| ☸️ | [What is wrong in this CFK cluster? Analyze a support bundle](/sessions?id=☸️-what-is-wrong-in-this-cfk-cluster) | nothing (`--sample`) |
| 📨 | [Produce realistic test data](/sessions?id=📨-produce-realistic-test-data) | a running environment |
| 📥 | [Read a topic: the last records, one offset, from a time, as JSON](/sessions?id=📥-read-a-topic) | a running environment |
| 📈 | [Is version Y slower? Benchmark two versions](/sessions?id=📈-is-version-y-slower-benchmark-two-versions) | a running example |
| 🐌 | [A slow or broken network, on purpose: degrade and block traffic](/sessions?id=🐌-a-slow-or-broken-network-on-purpose) | a running example |
| 🚚 | [Move a self-managed connector to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed) | Confluent Cloud, AWS credentials |
| 🏗️ | [Deploy a fully managed connector with Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform) | Confluent Cloud, terraform |

## 🕹️ Run an example: with the menu or with flags

New to the playground? Start here. `playground run` runs any example: without arguments it opens a menu that guides you
through the options of the example, and `playground run -f <example> <flags>` runs it directly, with the same options as
flags.

<video src="videos/session-run.mp4" poster="images/sessions/run.png" controls playsinline width="100%"></video>

**In this session**

- the menu: pick a category, find an example by typing a few words, then the options of that example, group by group
- versions: Confluent Platform (`--tag`, or one component only), connector (`--connector-tag`, `--connector-zip`,
  `--connector-jar`)
- add-ons toggled on and off (Grafana, kcat, Control Center, ksqlDB...), several at once with `<tab>`
- a bad combination (legacy Control Center with CP 8) blocks 🚀 in the menu, and is refused before anything is stopped
  with `-f`
- the same example under another security environment (`--environment sasl-ssl`), another connector version, DEBUG logs
  for the connector (`--connect-log-level`)
- `playground re-run`, `playground history`, `-o` to open the example files, `playground secrets set`

**Commands**

```bash
# the menu
playground run

# no menu: the example (absolute path, <tab> completion opens a picker) and the flags
playground run -f $PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh --tag 8.2.0 --connector-tag 10.8.12 --enable-jmx-grafana --enable-kcat
playground run -f $PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh --environment sasl-ssl --connector-tag 10.8.4 --connect-log-level io.confluent.connect.jdbc=DEBUG

playground re-run      # the last example again, same flags
playground history     # pick a previous run, edit its flags, run it
```

> [!TIP]
> Each run stops what was running before starting the example (`playground config container-kill-all-before-run false`
> to only stop the previous example).

**Links**

- 📚 [Start an example](/how-to-use?id=🏎️-start-an-example), [The playground run menu](/how-to-use?id=🕹️-the-playground-run-menu)
- 🧠 CLI reference: [playground run](/playground%20run), [playground re-run](/playground%20re-run),
  [playground history](/playground%20history)

## 🩺 A sink is RUNNING but writes nothing

The connector is `RUNNING`, its status shows no error, but nothing reaches the destination. One command says why, the dead
letter queue shows which records failed and the root cause, and once the cause is fixed the records are replayed.

<video src="videos/session-dlq.mp4" poster="images/sessions/dlq.png" controls playsinline width="100%"></video>

**In this session**

- `connector diagnose`: status, digest of the ERROR records, consumer lag and next steps, in one call
- `errors.tolerance=all`: why the task does not fail, and where the records went
- `topic dlq inspect`: records grouped by error, with the root cause and the original topic / partition / offsets
- fix the cause, then `topic dlq replay` (dry run first) and check that the sink caught up

**Commands**

```bash
playground connector diagnose --connector filestream-sink
playground topic dlq inspect --connector filestream-sink     # or --topic <dlq>, --grep, --json
playground topic dlq replay --connector filestream-sink --dry-run
playground topic dlq replay --connector filestream-sink      # --to <topic> to replay elsewhere
playground connector show-lag --connector filestream-sink --max-wait 120
```

Recorded on the example `other/reprocess-dlq-messages-with-sink-connector/replay-dlq-messages-with-playground.sh`
(schema-registry stopped while a FileStream sink converts Avro records).

**Links**

- 🧠 CLI reference: [playground connector diagnose](/playground%20connector%20diagnose),
  [playground topic dlq inspect](/playground%20topic%20dlq%20inspect), [playground topic dlq replay](/playground%20topic%20dlq%20replay)

## 🔀 What does this transform chain do to a record?

A customer sends a connector config with five transforms: records land in the wrong table, or the task fails in an SMT. The
SMT tester runs the chain step by step on a real record, with the classes and versions of the running worker.

<video src="videos/session-smt-test.mp4" poster="images/sessions/smt-test.png" controls playsinline width="100%"></video>

**In this session**

- the value, schema and topic after each step: a field renamed, a field added, the topic routed
- a `TimestampConverter` on a field that does not exist: a **silent no-op**, no error
- the step that throws, with its config and its error
- comparing CP versions (`--cp-version`), SMTs that are not in the worker (`--smt-plugin`, `--smt-jar`)

**Commands**

```bash
# the chain of a config on stdin, on a real record of a topic
playground connector smt test --from-topic orders --offset 0 < transforms.json

# the chain of a running connector, on a record of your own
playground connector smt test --connector my-sink --record '{"topic":"orders","value":{"id":1,"name":"foo"}}'
```

**Links**

- 🌐 <a href="reports/smt-test.html" target="_blank" rel="noopener">An SMT test report</a> (another chain, CP 7.9.0 vs 8.3.2: click around)
- 🧠 CLI reference: [playground connector smt test](/playground%20connector%20smt%20test)

## 🧑‍💻 The source code of a connector at the customer's version

A customer runs the JDBC sink 10.8.4: what does `batch.size` do, what is its default, and what changed since? The answers
are in the docs of the key and in the code at their exact tag, not on the main branch.

<video src="videos/session-sourcecode.mp4" poster="images/sessions/sourcecode.png" controls playsinline width="100%"></video>

**In this session**

- the docs of a config key, offline: doc, type, default, since when, values used in the examples
- the GitHub tree of a connector at an exact version, and the comparison of two versions
- a local checkout of that tag, to grep it
- fully managed connectors (resolved to their `v<version>-cloud` tag), `--open`, `--compile`

**Commands**

```bash
playground connector-plugin config-key --key batch.size --connector-class io.confluent.connect.jdbc.JdbcSinkConnector
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --only-show-url
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --connector-tag 10.9.9 --only-show-url
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --checkout-only
```

**Links**

- 🧠 CLI reference: [playground connector-plugin config-key](/playground%20connector-plugin%20config-key),
  [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode)

## 🐞 A breakpoint in a running connector: remote debugging

The logs are not enough: you want to see what the connector does with a record. The `connect` container always listens
for a Java debugger on port `5005`: get the code of the version that runs, attach a debugger, set a breakpoint, and inspect
the records as the connector sees them.

<video src="videos/session-remote-debugging.mp4" poster="images/sessions/remote-debugging.png" controls playsinline width="100%"></video>

**In this session**

- the version of the connector that runs, and its code at that tag, to know where to stop
- `jdb`, the debugger of the JDK, attached to `localhost:5005`, a breakpoint in `JdbcSinkTask.put` before the records are written
- `where`, `list`, `locals`, `print`: the call stack from the Connect framework, the source, the batch, the value of a record
- the same in Visual Studio Code (and IntelliJ IDEA): an attach configuration on `127.0.0.1:5005`

**Commands**

```bash
playground connector versions
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.9.9 --checkout-only
jdb -attach localhost:5005 -sourcepath /tmp/connector-plugin-sourcecode/kafka-connect-jdbc-10.9.9/src/main/java
# in jdb: stop at io.confluent.connect.jdbc.sink.JdbcSinkTask:87, then where, list, locals, print first.value(), clear, cont

# another container than connect (broker, schema-registry...): also prints the launch.json entry for VS Code
playground debug enable-remote-debugging -c broker
```

> [!WARNING]
> `stop at` suspends every thread of the worker: keep the pause short (the worker and consumer groups time out), then
> `clear` the breakpoint and `cont`.

**Links**

- 📚 Step by step with Visual Studio Code: [✨ Remote debugging](/reusables?id=✨-remote-debugging) in the Reproduction toolkit
- 🧠 CLI reference: [playground debug enable-remote-debugging](/playground%20debug%20enable-remote-debugging),
  [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode)

## 🧵 A connector looks stuck: analyze thread dumps

The task is `RUNNING`, but no record moves and there is no error in the logs. Three thread dumps of the worker, a few
seconds apart, show which threads are stuck, blocked or burning CPU.

<video src="videos/session-thread-dump.mp4" poster="images/sessions/thread-dump.png" controls playsinline width="100%"></video>

**In this session**

- the 3 ways to run it: live on a running example, on dumps sent by a customer, on a sample shipped with the playground
- reading the findings, most severe first: deadlock, lock contention, stuck Connect task, CPU-hot thread, leaking thread pool
- from the stuck frame to the code: the connector source code at the customer's version
- the HTML report to share

**Commands**

```bash
# live, on a running example: 3 dumps 5 s apart, then the analysis
playground analyze thread-dump -c connect

# on dumps from a customer: one -f per dump of the same JVM
playground analyze thread-dump -f dump1.txt -f dump2.txt -f dump3.txt

# on the sample used in the session
playground analyze thread-dump --sample deadlock_jdk21 --output-dir /tmp/thread-dump
```

**Links**

- 🌐 <a href="reports/thread-dump.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze thread-dump](/playground%20analyze%20thread-dump)
- 🔗 Next step: [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode)

## ♻️ Long GC pauses or a memory leak: analyze GC logs

The worker freezes, tasks get rebalanced, the heap keeps growing. Every GC pause stops all the threads of the JVM: the GC
log says how long each pause was, why it happened, and how full the heap was before and after.

<video src="videos/session-gc-logs.mp4" poster="images/sessions/gc-logs.png" controls playsinline width="100%"></video>

**In this session**

- live on a running example, on GC logs from a customer (JDK 7 to 21, any collector), on a sample
- health score, pause times and distribution, live set, causes, longest pauses
- recommendations with the JVM flag to try (`-Xmx`, `-XX:G1ReservePercent`)
- a heap floor that keeps rising = a leak: the next step is a heap dump

**Commands**

```bash
playground analyze gc-logs -c connect
playground analyze gc-logs -f gc.log                       # a file, or a folder of rotated logs
playground analyze gc-logs --sample jdk21_g1_kafka_real --output-dir /tmp/gc-logs
```

**Links**

- 🌐 <a href="reports/gc-logs.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze gc-logs](/playground%20analyze%20gc-logs), next step [playground analyze heap-dump](/playground%20analyze%20heap-dump)

## 🛩️ A slow connector: where does the task time go?

The connector works, but it is slow. Is it the database, the network, Kafka, a lock, the converters, or the connector code
itself? Java Flight Recorder samples what every thread does, with almost no overhead, and the digest answers with numbers.

<video src="videos/session-flight-recorder.mp4" poster="images/sessions/flight-recorder.png" controls playsinline width="100%"></video>

**In this session**

- a recording over JMX on a running example (no restart), or a `.jfr` from a customer, or a sample
- task time by state: running, blocked on network I/O, in the Kafka client
- CPU by layer (connector, converters, Kafka client, drivers), hot methods, network calls by remote, allocation
- what was checked and found normal (lock contention, exceptions, GC pauses)

**Commands**

```bash
playground analyze flight-recorder -c connect --duration 60s --connector <connector>
playground analyze flight-recorder -f rec.jfr              # jcmd <pid> JFR.start duration=60s filename=rec.jfr
playground analyze flight-recorder --sample jdbc_postgres_sink --output-dir /tmp/flight-recorder
```

**Links**

- 🌐 <a href="reports/flight-recorder.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze flight-recorder](/playground%20analyze%20flight-recorder)

## 🅾️ Oracle XStream CDC lags or is idle

The Oracle XStream CDC source is `RUNNING`, but no change comes in, or it lags. The answer is on the database side, in the
`orclcdc_diag_<date>.html` report the customer generates with `orclcdc_diag.sql`: hundreds of tables, digested into findings.

<video src="videos/session-oracle-xstream-report.mp4" poster="images/sessions/oracle-xstream-report.png" controls playsinline width="100%"></video>

**In this session**

- prerequisites (ARCHIVELOG, supplemental logging, streams pool), capture, LogMiner, outbound server
- findings most severe first, each quoted from its section of the report, with the SQL to fix it
- root-cause patterns (undersized streams pool, flow control, aborted capture...)
- comparing two reports (`-f` twice), the symptom given with `-p`

**Commands**

```bash
playground analyze oracle-xstream-report -f orclcdc_diag_<date>.html -p "no change since 9:10"
playground analyze oracle-xstream-report -c oracle         # on the playground XStream example
playground analyze oracle-xstream-report --sample synthetic_failures --output-dir /tmp/xstream
```

**Links**

- 🌐 <a href="reports/oracle-xstream-report.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze oracle-xstream-report](/playground%20analyze%20oracle-xstream-report)

## ☸️ What is wrong in this CFK cluster?

A Confluent for Kubernetes cluster is broken and the customer sends a support bundle: pod logs, CR yamls, events and pod
states. The analyzer sorts it into issues by severity and component, with a timeline of the recent changes.

<video src="videos/session-cfk-bundle.mp4" poster="images/sessions/cfk-bundle.png" controls playsinline width="100%"></video>

**In this session**

- a folder, `.tar.gz` or `.zip` analyzed in a container, secrets / IPs / hostnames sanitized
- versions, recent changes, and issues by category: pod failures, OOMKilled, probes, TLS, authentication...
- the `Caused by:` chain of each finding, the kubectl commands to run next, the CFK docs
- focusing with `--component`, `--severity`, `--top`

**Commands**

```bash
playground analyze cfk-bundle --bundle support-bundle.tar.gz
playground analyze cfk-bundle --bundle support-bundle.tar.gz --component connect --severity high
playground analyze cfk-bundle --sample synthetic --output-dir /tmp/cfk-bundle
```

**Links**

- 🌐 <a href="reports/cfk-bundle.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze cfk-bundle](/playground%20analyze%20cfk-bundle)

## 📨 Produce realistic test data

You need records like the customer's: give a schema, get random records that match it, with the schema registered for you,
on any environment (SASL, mTLS, Confluent Cloud).

<video src="videos/session-topic-produce.mp4" poster="images/sessions/topic-produce.png" controls playsinline width="100%"></video>

**In this session**

- random records from an Avro, JSON Schema or Protobuf schema, with a key and headers, read back with `topic consume`
- a schema derived from one JSON record (`--derive-value-schema-as`)
- datagen schemas, tombstones, big records (`--record-size`)
- a steady flow until ctrl-c (`--nb-messages -1 --throughput 20`): the progress every 10 seconds, and the exact number of records sent
- `--forced-value`, `--value-format raw`, `--validate`, subject name strategies, compression

**Commands**

```bash
playground topic produce -t leads --nb-messages 5 --key 'lead-%g' --headers 'source:web,version:2' < scripts/cli/predefined-schemas/avro/lead.avsc
echo '{"order_id": 1, "customer": "acme", "amount": 9.99, "paid": true}' | playground topic produce -t payments --nb-messages 3 --derive-value-schema-as AVRO
playground topic produce -t trades --nb-messages 3 < scripts/cli/predefined-schemas/datagen/stock_trades_schema.avro
playground topic produce -t leads --tombstone --key 'lead-1'
playground topic produce -t big --nb-messages 2 --record-size 1000000 < scripts/cli/predefined-schemas/avro/lead.avsc
playground topic produce -t ticks --nb-messages -1 --throughput 20 --value '{"tick": %g}'     # ctrl-c to stop
playground topic consume -t ticks --count
```

**Links**

- 🧠 CLI reference: [playground topic produce](/playground%20topic%20produce) (an example for each flag)

## 📥 Read a topic

`playground topic consume` finds the format on its own (Avro, Protobuf, JSON Schema, plain) and reads from the beginning.
On a big topic the first 100 records are rarely the ones you want: show the last ones, the record a connector is stuck on,
what arrived during an incident, or the records as JSON for `jq`. And when an example checks that data flowed, records
that cannot be deserialized are caught.

<video src="videos/session-topic-consume.mp4" poster="images/sessions/topic-consume.png" controls playsinline width="100%"></video>

**In this session**

- `--last N`: the most recent records, sorted by timestamp across the partitions
- `--partition 1 --offset 42`: the record a connector is stuck on
- `--from-timestamp 20s` (or a date, an epoch, `10m`, `2h`): what arrived from that time
- `--json`: one object per record, only the records on stdout, piped to `jq`
- `--count` (with `--grep`): records, not offsets
- `--min-expected-messages`: 5 offsets, but 2 records that are not Avro, so the check fails and says why

**Commands**

```bash
playground topic consume -t orders --last 3
playground topic consume -t orders --partition 1 --offset 42 --max-messages 1
playground topic consume -t orders --from-timestamp 20s                          # or "2026-10-22 10:30", 1792660170522, 10m, 2h
playground topic consume -t orders --last 3 --json | jq -c '{key, partition, offset, quantity: .value.quantity}'
playground topic consume -t orders --count --grep order-7
playground topic consume -t payments --min-expected-messages 5
```

**Links**

- 🧠 CLI reference: [playground topic consume](/playground%20topic%20consume) (an example for each flag)

## 📈 Is version Y slower? Benchmark two versions

Since the upgrade, the JDBC sink feels slower. `connector benchmark` measures it on the example you run: for each version it
switches the plugin, warms up, drains a backlog and records the workers, then compares the versions.

<video src="videos/session-benchmark.mp4" poster="images/sessions/benchmark.png" controls playsinline width="100%"></video>

**In this session**

- drain mode: pause, load `--nb-records`, resume, time the drain (no load script needed for a sink)
- two `--connector-tag`: the comparison of the versions, the original version restored at the end
- records/s, put batch time, running ratio, CPU, GC, and the flight recording of the measure
- lower bounds, benchmark history, sources and fully managed connectors

**Commands**

```bash
playground connector benchmark --nb-records 3000000 --connector-tag 10.8.4 --connector-tag 10.9.9 --output-dir /tmp/benchmark
playground connector benchmark --mode steady --duration 5m          # a throughput over a duration instead of a drain
```

**Links**

- 🌐 <a href="reports/benchmark.html" target="_blank" rel="noopener">A benchmark report</a> (JDBC PostgreSQL sink 10.8.4 vs 10.9.9: click around)
- 🧠 CLI reference: [playground connector benchmark](/playground%20connector%20benchmark), and
  [⏱️ Benchmark a connector](/reusables?id=⏱️-benchmark-a-connector) in the Reproduction toolkit

## 🐌 A slow or broken network, on purpose

The customer blames the network: timeouts, a connector that fails during the night, rebalances on a slow link. Make the
network slow, lossy or cut, on the example you run, without changing the example or restarting a container, and see what
the connector does, and whether it recovers when the network comes back.

<video src="videos/session-network-traffic.mp4" poster="images/sessions/network-traffic.png" controls playsinline width="100%"></video>

**In this session**

- `debug degrade-traffic`: latency, jitter, loss, corruption, duplicates or a bandwidth limit with `tc netem`, run from a
  netshoot container in the network namespace of the container (nothing installed, any image)
- `tc` only delays what a container **sends**: `--latency 200ms` on connect adds 200 ms to the round trip, degrade the
  other side too for 400 ms
- each container keeps its own degradation until it is stopped or replaced by a new `--action start`
- several effects in one call, scoped to one `--port`; `--action status` shows what is applied and measures the round trip
- `debug block-traffic`: an `iptables` DROP, like a firewall: no error comes back, the client waits for its own timeout
- the JDBC sink fails with `SocketTimeoutException: Connect timed out`, and stays `FAILED` once the network is back: it
  needs a restart

**Commands**

```bash
playground debug degrade-traffic -c connect --destination postgres --action status
playground debug degrade-traffic -c connect --destination postgres --latency 200ms --action start
playground debug degrade-traffic -c postgres --destination connect --latency 200ms --action start      # both ways
playground debug degrade-traffic -c postgres --action stop                                               # each container keeps its own
playground debug degrade-traffic -c connect --destination postgres --port 5432 --latency 100ms --jitter 50ms --loss 5% --action start
playground debug degrade-traffic -c connect --action stop

playground debug block-traffic -c connect --destination postgres --port 5432 --action start
playground connector wait --connector postgres-sink --state FAILED --max-wait 300
playground container logs -c connect --errors --since 5m
playground debug block-traffic -c connect --destination postgres --port 5432 --action stop              # same flags as start
playground connector restart --connector postgres-sink
```

Recorded on the example `connect/connect-jdbc-postgresql-sink/postgres-sink.sh`.

> [!TIP]
> Without `--destination`, `degrade-traffic` applies to all the traffic of the container: use it when the destination
> has IP addresses that change (Confluent Cloud, a SaaS API). A container restart removes both the degradation and the
> block. Each `block-traffic --action start` adds one `iptables` rule and each `--action stop` removes one: started twice,
> stop twice (the `iptables-save` printed at the end shows what is left).

**Links**

- 🍪 Deep dive: [`block-traffic` and `degrade-traffic` under the hood, hands-on lab and repro recipes](/deep-dive-network-traffic.md)
- 📖 [Blocking traffic](/reusables?id=🚫-blocking-traffic) and [Degrade traffic](/reusables?id=🐌-degrade-traffic---add-latency-packet-loss-or-corruption)
  in the Reproduction toolkit
- 🧠 CLI reference: [playground debug degrade-traffic](/playground%20debug%20degrade-traffic),
  [playground debug block-traffic](/playground%20debug%20block-traffic), [playground connector wait](/playground%20connector%20wait)

## 🚚 Move a self-managed connector to fully managed

A customer wants to move a self-managed connector to Confluent Cloud: what does its configuration become, and will the move
lose or replay data? Rehearse it with the [Connector Migration Utility](https://github.com/confluentinc/connect-migration-utility):
a local Connect worker connected to Confluent Cloud runs the self-managed connector, `discovery` writes its fully managed
configuration, `migrate` creates the fully managed connector from the offsets of the self-managed one.

<video src="videos/session-connect-migration.mp4" poster="images/sessions/connect-migration.png" controls playsinline width="100%"></video>

**In this session**

- the self-managed AWS CloudWatch Metrics sink, RUNNING on a local worker connected to Confluent Cloud
- `discovery`: the summary (what can move, what cannot and why) and the generated fully managed configuration
  (`AwsCloudWatchMetricsSinkConnector` becomes `CloudWatchMetricsSink`, the Avro converter becomes `input.data.format`,
  secrets redacted)
- the three migration modes, and `stop_create_latest_offset`: no loss, no duplicates
- `migrate`: the secrets passed again with `--sensitive-property`, the fully managed connector RUNNING, the self-managed one
  STOPPED

**Commands**

```bash
playground run -f ccloud/connect-migration-utility/cloudwatch-metrics-sink.sh   # the example (Confluent Cloud + AWS credentials)

playground connector connect-migration-utility discovery
playground connector connect-migration-utility migrate --migration-mode stop_create_latest_offset \
  --sensitive-property 'aws.access.key.id=$AWS_ACCESS_KEY_ID' --sensitive-property 'aws.secret.access.key=$AWS_SECRET_ACCESS_KEY'
# --no-open: do not open the generated configs in the editor, nor the connector in the browser (scripts, agents)
```

| `--migration-mode` | Starts from | Self-managed connector | Trade-off |
| --- | --- | --- | --- |
| `create` (default) | no offsets | keeps running | replays or skips data, depending on the connector |
| `create_latest_offset` | its latest offsets | keeps running | no downtime, some duplicates while both run |
| `stop_create_latest_offset` | its latest offsets | stopped first | no loss, no duplicates |

> [!WARNING]
> Pass the secrets with single quotes (`'aws.secret.access.key=$AWS_SECRET_ACCESS_KEY'`): `migrate` expands the variable
> itself, so the value does not show in your terminal or shell history. After `migrate`, the configurations in
> `connect-migration-utility-discovery-output/` hold the real secrets: delete that folder when you are done. The fully
> managed connector is billed: delete it with `playground connector delete` once the rehearsal is over.

**Links**

- 📁 The example: [ccloud/connect-migration-utility](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-migration-utility)
- 🧠 CLI reference: [playground connector connect-migration-utility discovery](/playground%20connector%20connect-migration-utility%20discovery),
  [playground connector connect-migration-utility migrate](/playground%20connector%20connect-migration-utility%20migrate)
- 📚 The utility, its modes and the supported connectors: [confluentinc/connect-migration-utility](https://github.com/confluentinc/connect-migration-utility)

## 🏗️ Deploy a fully managed connector with Terraform

The customer manages their fully managed connectors with Terraform: deploy the connector of a playground example the same
way, from the same JSON config, and see the HCL it becomes. Running it again updates the connector in place, and deleting it
runs `terraform destroy`.

<video src="videos/session-terraform.mp4" poster="images/sessions/terraform.png" controls playsinline width="100%"></video>

**In this session**

- `--terraform`: the JSON config of the Datagen example becomes HCL, then `terraform init`, `plan` and `apply`
- the secrets in `config_sensitive`, masked in the output
- the folder of the connector, with its `connector.tf` and its state
- a changed config, the same command: the plan shows `~ "max.interval" = "10000" -> "1000"`, the connector is updated in place
- `connector delete` runs `terraform destroy`

**Commands**

```bash
envsubst < /tmp/datagen.json | playground connector create-or-update -c DatagenSource_playground --terraform --wait
terraform -chdir=$(ls -d .terraform-playground/DatagenSource_playground-*) state list
sed -i '' 's/"10000"/"1000"/' /tmp/datagen.json
envsubst < /tmp/datagen.json | playground connector create-or-update -c DatagenSource_playground --terraform
playground topic consume -t datagen_pageviews --last 3
playground connector delete --connector DatagenSource_playground
```

Recorded on the example `ccloud/fm-datagen-source/fully-managed-datagen-source.sh`: its config in `/tmp/datagen.json`, with
`"$CLOUD_KEY"` / `"$CLOUD_SECRET"` placeholders replaced by `envsubst`.

**Links**

- 📖 [Fully managed connectors with Terraform](/reusables?id=🏗️-fully-managed-connectors-with-terraform)
- 🧠 CLI reference: [playground connector create-or-update](/playground%20connector%20create-or-update),
  [playground connector delete](/playground%20connector%20delete)
