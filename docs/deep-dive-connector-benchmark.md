# 🍪 Deep dive: `playground connector benchmark`

The command that answers "how fast is this connector?" and "is version Y slower?" on the example you run: it loads a
backlog (or a steady flow), measures how many records per second the connector processes from its own JMX metrics,
records the worker with Java Flight Recorder, says where the task time went, and compares the run with the previous
one or with other plugin versions. Takes about 15 minutes to read and run.

> [!TIP]
> In a hurry? Watch the short video session [📈 Is version Y slower? Benchmark two versions](/sessions?id=📈-is-version-y-slower-benchmark-two-versions)
> first. This page goes further: what exactly is measured, where the load comes from, the traps of a local
> benchmark, a hands-on lab and recipes for support repros.

| You want | Command |
| --- | --- |
| the throughput of the running connector, reproducible | `playground connector benchmark` (drain of `--nb-records 100000`) |
| a bigger backlog | `… --nb-records 1000000` |
| the throughput under a continuous load | `… --mode steady --duration 5m` (`--warmup 30s`) |
| the end-to-end latency of a source | `… --mode steady` (p50 / p95 / p99 from a timestamp field of the records) |
| two plugin versions compared | `… --connector-tag 10.8.4 --connector-tag 10.9.9` (`--rounds 2`) |
| another load shape (source) | `… --shape small-txn` / `update` / `delete`, or a sequence `bulk,update,delete` |
| the result as data | `… --json` (the result JSON on stdout, logs on stderr) |
| your own load | `… --load-command "<cmd>"` / `--stream-load-command "<cmd>"`, or `BENCHMARK_LOAD_SCRIPT=<file>` |
| right after the example | `playground run -f <example> --benchmark` (flags in `BENCHMARK_ARGS="--nb-records 1000000"`) |

---

## 1. Mental model (the 3 things to remember)

1. **A drain measures the connector, a steady run measures the slower of the load and the connector.**
   - `--mode drain` (default): pause the connector, load `--nb-records` records, resume it, and time how long it takes
     to process the backlog. The load is done **before** the measure, so its speed doesn't count: this is the most
     reproducible number, the one to compare between versions or configs.
   - `--mode steady`: start the load in the background, wait `--warmup`, then measure for `--duration`. If the
     connector simply keeps up with the load, the summary says so (`the connector kept up with the load … this is the
     speed of the load, not of the connector`): the number is then the load's. Its use is the **end-to-end latency** of
     a source, which a drain can't give (in a drain, a record's latency is the time it waited in the backlog).

2. **The load comes from the example.** You don't write a load to benchmark an example:
   - **a sink**: the `playground topic produce` of the example script that feeds the connector's topics is replayed
     with `--nb-messages <n>` (same schema, key and headers);
   - **a source**: the `benchmark-load.bash` next to the example script, called with `--records <n> --mode
     preload|stream --shape …` (rows in the `CUSTOMERS` table of the database examples, messages for the brokers,
     files for the file and object-store examples, lines appended to the file for FileStream). It's called with
     `--check` first, so that an unsupported combination fails before the connector is paused;
   - **or** `--load-command` / `--stream-load-command`, which take precedence, or `BENCHMARK_LOAD_SCRIPT=<file>` for
     another load script of the example's folder (one per reproduction model, for instance).

3. **Numbers are relative to this machine.** Everything (broker, connect, the external system, the load) shares one
   Docker host: compare runs on the same machine only, and never quote a local number as "what the connector does in
   production". Each result records its setup (host CPU and memory, container engine resources, connect image, JVM
   and heap, workers, brokers, connector config with secrets masked), and the summary warns when the previous run was
   on a different setup, with or without the flight recorder, or with Grafana running.

---

## 2. What is measured, exactly

The throughput comes from the **connect JMX metrics of the tasks**, sampled every `--interval` (5 s):

| Connector | Counter | Includes |
| --- | --- | --- |
| sink | `sink-record-read-total` | records read from Kafka, **including** the ones filtered by an SMT or sent to the DLQ |
| source | `source-record-write-total` | records written to Kafka |

What the summary prints (one `printf` line each):

```text
🏁 benchmark of 🌎onprem connector filestream-source (source, 1 task(s), org.apache.kafka.connect.file.FileStreamSourceConnector 8.3.2-ce, CP 8.3.2)
   mode                   drain of 200000 records (shape bulk, loaded in 0.7s)
   throughput             ≥ 25974.0 records/s   (the backlog was processed before the first sample)
   put batch avg          … ms
   running ratio avg      …
   connect cpu avg / max  …% / …% of one core (…% of the cpus available)
   gc pauses              …% of the time
   records per task       …
   dlq / dropped          0 records sent to the dlq, 0 dropped without dlq
   setup                  …
   flight recorder        … where the task time went …
   previous run           … records/s on <date>: +3%
⚠️ results are relative to this docker host: compare runs on the same machine only
📄 samples: /tmp/playground-benchmark/<run>.csv
📄 result: /tmp/playground-benchmark/<run>.json
📊 report: /tmp/playground-benchmark/<run>.html
```

Gotchas:

- **"≥ N records/s" is a lower bound**, not a result: the backlog was processed before the first sample, or (fully
  managed sink) fewer than 5 offset commits were seen. Rerun with 10x `--nb-records`. Lower bounds are left out of
  the comparisons.
- **A drain of a few seconds has few samples**: `only N samples during the measure: the percentiles are not
  meaningful`. A good drain lasts tens of seconds: raise `--nb-records`, or lower `--interval`.
- **The first records after the resume are not measured**: tasks take a moment to restart (`▶️ first records after
  Ns (not measured), measuring the remaining … records`).
- **A backlog processed before the first sample gives a lower bound**: `throughput ≥ 25974.0 records/s (the backlog
  was processed before the first sample)` and `⚠️ … the throughput is a lower bound: increase --nb-records (10x) for a
  real measure`. FileStream drains 200000 records in a few seconds: that's what happens in the lab below.
- **The flight recorder costs a few % of throughput** (it records the workers over JMX for the measure, then the
  summary and the report say where the task time went: running, blocked on the external system, Kafka client, locks,
  converters, SMTs…). `--no-flight-recorder` for a raw number, but compare like with like: the summary warns when the
  previous run wasn't recorded the same way.
- **The sink count includes what the connector reads, not only what it writes**: a sink dropping records (SMT
  filter, `errors.tolerance=all` + DLQ) looks fast. The `dlq / dropped` line tells.
- Results are appended to `benchmark-history` at the root of the repository (`--no-history` to skip it), and the
  next run of the same connector in the same example is compared with it (`--compare <result.json>` for another one).
- The HTML report (charts, setup, flight recorder digest) opens in the browser only in an interactive terminal.

---

## 3. Steady mode and the latency of a source

```bash
playground connector benchmark --mode steady --duration 5m --warmup 30s
playground connector benchmark --mode steady --duration 2m --shape small-txn --latency-field create_ts
```

- The stream load prints `BENCHMARK_BATCH=<records> <epoch>` per batch and stops at a batch boundary at the end of the
  measure (`🛑 stopping the load at the end of its current batch`): killing a producer mid-batch can send a truncated
  record.
- **End-to-end latency** (sources): Kafka record timestamp − the time of the change in the source system, read from
  the records written during the measure (all of them up to 100000, otherwise a sample of 5 slices). The field is
  `--latency-field <dotted path>`, or the one the load announces (`BENCHMARK_LATENCY_FIELD=create_ts` for the
  `CUSTOMERS` table, `update_ts` with `--shape update`), or `source.ts_ms` of a CDC envelope (commit time), or
  `wallTime` / `clusterTime` of a MongoDB change event. `--no-latency` disables it.
- Latency warnings: negative values (clock skew between containers), a 1 s precision (MySQL `TIMESTAMP` without
  fractional seconds), all 0 ms (the connector sets the record timestamp from the source field).
- Prefer `--shape small-txn` for latency: with `bulk`, a default `CURRENT_TIMESTAMP` is the start of the transaction
  of a whole batch, so every row looks as old as the batch.
- A FileStream source has no time field in its lines: steady mode measures the throughput only (`end-to-end latency`
  explains why: `end-to-end latency     the values of the records are not json, avro, protobuf or json schema`).

---

## 4. Comparing: versions, shapes, sessions, fully managed

```bash
# two (or more) plugin versions, original version restored at the end
playground connector benchmark --nb-records 3000000 --connector-tag 10.8.4 --connector-tag 10.9.9 --rounds 2

# one drain per shape on the same rows (sources with a benchmark-load.bash)
playground connector benchmark --shape bulk,update,delete

# the load in parallel sessions
playground connector benchmark --sessions 4
```

| Option | What happens |
| --- | --- |
| `--connector-tag A --connector-tag B` | for each version: `update-version --connector-tag`, a check that the worker really runs it, a warm-up drain (not recorded), the measured drain(s), then a comparison table (`version, runs, lower bounds, records/s (mean), min, max, vs first`) and the original version restored |
| `--shape bulk,update,delete` | a series of drains of the load script, compared per phase; `delete` counts tombstones from the connector config (`tombstones.on.delete`…), refused for a JDBC source |
| `--sessions <n>` | the `benchmark-load.bash` in n parallel sessions (not with `--load-command` or a replayed produce) |

Gotchas:

- **`--connector-tag` needs a connector installed from Confluent Hub** (the `CONNECT_PLUGIN_PATH` of the example's
  compose file): a built-in plugin like FileStream has no versions to switch (`❌ could not find the confluent hub
  plugin of org.apache.kafka.connect.file.FileStreamSinkConnector in the example (CONNECT_PLUGIN_PATH of its docker
  compose file): --connector-tag needs a connector installed from confluent hub`, exit 1).
- **Fully managed connectors**: sources whose `ccloud/fm-*` example ships a `benchmark-load.bash` (records counted from
  the topics' end offsets), and sinks (produce replay, records counted from the offsets committed by `connect-<lcc
  id>`, which move about once a minute: drains of 10+ commits, often 1M records). No JMX, flight recorder nor
  `--connector-tag`; the Confluent Cloud Metrics API gives the steady rate of the full minutes. The throughput
  includes the network between your machine and Confluent Cloud.
- Not available on the CFK environment yet.

---

## 5. From `playground run`

- `playground run -f <example> --benchmark` (also a toggle in the `run` menu) runs `connector benchmark` right after
  the example succeeds, and exits with its code when it fails. `--benchmark` takes no value: the flags of
  `connector benchmark` go in the `BENCHMARK_ARGS` environment variable, for instance a backlog of 10 million records
  of 100 bytes for the spool dir source:

  ```bash
  BENCHMARK_ARGS="--nb-records 10000000 --record-size 100" \
    playground run -f connect/connect-spool-dir-source/csv.sh --benchmark
  ```

  `playground run … --benchmark "--nb-records 10000000"` fails with `invalid argument`, and the
  `BENCHMARK_LOAD_RECORDS` / `BENCHMARK_LOAD_RECORD_SIZE` variables seen in the load scripts are not inputs: they are
  set from `--nb-records` / `--record-size` by `benchmark_load_args`.
- `playground run -f <example> --enable-sql-datagen` uses the same load scripts: after the example, one-row
  transactions are streamed from `SQL_DATAGEN_SESSIONS` (5) sessions for `SQL_DATAGEN_DURATION` (10) minutes, to watch
  a source under load (with `--enable-jmx-grafana`, for instance).

---

## 6. Hands-on lab (≈15 min)

**Step 1: a sink, in drain mode**

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh
playground connector benchmark --nb-records 200000 --output-dir /tmp/benchmark-lab
# 🔁 load: replay of the 'playground topic produce' of filestream-sink.sh to topic filestream
# ⏸️ pausing 🌎onprem connector filestream-sink (sink, 1 task(s), org.apache.kafka.connect.file.FileStreamSinkConnector 8.3.2-ce)
# 📥 loading the backlog: …
# 📦 backlog of 200000 records loaded in …s
# ⏯️ resuming 🌎onprem connector filestream-sink and waiting for 200000 records (max 1800s, sample every 5s)
# 🏁 benchmark of 🌎onprem connector filestream-sink (sink, 1 task(s), …)
#    throughput             ≥ 25974.0 records/s   (the backlog was processed before the first sample)
# ⚠️ the backlog was processed before the first sample, the throughput is a lower bound: increase --nb-records (10x) for a real measure
# 📊 report: /tmp/benchmark-lab/….html
```

**Step 2: again, as JSON, and compared with step 1**

```bash
playground connector benchmark --nb-records 200000 --output-dir /tmp/benchmark-lab --json 2> /dev/null \
  | jq '{records, seconds, records_per_second, lower_bound, tasks, plugin_version, cp_tag}'
# { "records": 200000, "seconds": 7.7, "records_per_second": 25974.0, "lower_bound": true, "tasks": 1, "plugin_version": "8.3.2-ce", "cp_tag": "8.3.2" }
```

With `--json`, stdout only holds the result. The human summary of step 1 already compared with the last saved run of
the same connector (`previous run           263157.9 records/s on 2026-10-15T10:22:02Z: -90%`, with a warning when one
run had the flight recorder and the other not).

**Step 3: a source, with its `benchmark-load.bash`**

```bash
playground run -f connect/connect-filestream-source/filestream-source.sh
playground connector benchmark --nb-records 200000 --output-dir /tmp/benchmark-lab
# 📥 loading the backlog: bash "…/connect/connect-filestream-source/benchmark-load.bash" --records 200000 --mode preload --shape bulk …
# 📦 backlog of 200000 records loaded in 0.7s
# 🏁 benchmark of 🌎onprem connector filestream-source (source, 1 task(s), …)
playground connector benchmark --shape update; echo "exit=$?"
# ❌ --shape update does not apply to lines appended to a file: use the default --shape bulk
# exit=1
```

**Step 4: steady mode**

```bash
playground connector benchmark --mode steady --duration 1m --warmup 10s --nb-records 20000 --output-dir /tmp/benchmark-lab
# 🌊 starting the load in the background: …
# 🔥 warm-up for 10s
# ⏱️ measuring for 60s (sample every 5s)
# 🛑 stopping the load at the end of its current batch
#    mode                   steady for 63.4s after 10s of warm-up
#    throughput             57728.7 records/s   (per 5s sample: p50 56717.8  p95 61457.8  min 52264.8)
#    end-to-end latency     the values of the records are not json, avro, protobuf or json schema
# ⚠️ the connector kept up with the load (3660000 records processed, 3720000 generated during the measure): this is the speed of the load, not of the connector, use --mode drain to measure its maximum
```

**Step 5: why versions can't be compared here**

```bash
playground connector benchmark --connector-tag 1.0.0 --connector-tag 1.0.1; echo "exit=$?"
# ❌ could not find the confluent hub plugin of org.apache.kafka.connect.file.FileStreamSourceConnector in the example (CONNECT_PLUGIN_PATH of its docker compose file): --connector-tag needs a connector installed from confluent hub
# exit=1
```

Run the same with a Hub connector (the JDBC sink of the 📈 session) to see the comparison table.

```bash
playground stop
```

---

## 7. Recipes for support repros

| Customer question | Command |
| --- | --- |
| "it got slower after the upgrade" | `--connector-tag <old> --connector-tag <new> --rounds 2` on the example closest to their setup, with their `tasks.max` and batch settings in the config |
| "is this config faster?" (batch size, `tasks.max`, `max.poll.records`) | drain, `create-or-update` with the new value, drain again: the `previous run … ±N%` line compares them |
| "why is it slow?" | the flight recorder lines of the summary (time blocked on the external system vs CPU in converters / SMTs / the connector), then [`analyze flight-recorder`](/deep-dive-jvm-diagnostics.md) on the kept `.jfr` |
| "what latency should we expect from this source?" | `--mode steady --shape small-txn` with a load below the throughput of a drain: p50 / p95 / p99 |
| "updates are slower than inserts" | `--shape bulk,update` on a source with a `benchmark-load.bash` |
| "how many tasks do we need?" | drains with `tasks.max` 1, 2, 4 (`records per task` shows whether the work is spread) |
| "our table, not the CUSTOMERS one" | a `benchmark-load-<ticket>.bash` in the repro model and `BENCHMARK_LOAD_SCRIPT=benchmark-load-<ticket>.bash` (replace the symlink to the example's load with a file first) |
| "fully managed is slower than self-managed" | the `ccloud/fm-*` example with a `benchmark-load.bash`: drains of 1M records, and the Metrics API line; remember the network to Confluent Cloud is in the number |

Always say in the ticket that the numbers are from a laptop: give the **ratio** between versions or configs, not
the records/s.

---

## 8. Cheat sheet

```bash
playground connector benchmark [--connector <c>] [--mode drain|steady] [--nb-records 100000] [--record-size N]
  [--duration 5m] [--warmup 30s] [--interval 5s] [--max-wait 30m]
  [--shape bulk|small-txn|update|delete|bulk,update,…] [--sessions N]
  [--connector-tag A --connector-tag B [--rounds 2]]
  [--load-command "<cmd>"] [--stream-load-command "<cmd>"] [--topic <t>]
  [--latency-field <path>] [--no-latency] [--no-flight-recorder]
  [--output-dir /tmp/playground-benchmark] [--compare <result.json>] [--no-history] [--json]
BENCHMARK_LOAD_SCRIPT=<file> playground connector benchmark …
BENCHMARK_ARGS="--nb-records 1000000 --record-size 100" playground run -f <example> --benchmark
playground run -f <example> --enable-sql-datagen
```

- Drain = the connector's speed (load before the measure). Steady = the slower of load and connector, plus latency.
- Sink: the example's `topic produce` is replayed. Source: its `benchmark-load.bash`.
- JMX counters (`sink-record-read-total` / `source-record-write-total`); `≥` = lower bound, rerun with 10x records.
- Relative to this machine: compare ratios, same setup, same flight recorder setting.
- Sources: [`connector/benchmark.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/benchmark.sh),
  `benchmark_*` load helpers in
  [`utils_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/utils_function.sh),
  [`tools/benchmark-report/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/tools/benchmark-report).

---

**Links**

- 🎬 Video session: [📈 Is version Y slower? Benchmark two versions](/sessions?id=📈-is-version-y-slower-benchmark-two-versions),
  and <a href="reports/benchmark.html" target="_blank" rel="noopener">a benchmark report</a> to click around
- 📖 [⏱️ Benchmark a connector](/toolkit-performance?id=⏱️-benchmark-a-connector) in the Reproduction toolkit (load scripts, a table of your own)
- 🍪 Deep dives: [JVM diagnostics](/deep-dive-jvm-diagnostics.md) (the flight recording of the measure),
  [offsets and lag](/deep-dive-offsets-and-lag.md) (`show-lag` while a sink drains),
  [running examples and changing versions](/deep-dive-run-and-versions.md) (`update-version --connector-tag`)
- 🧠 CLI reference: [playground connector benchmark](/playground%20connector%20benchmark)
