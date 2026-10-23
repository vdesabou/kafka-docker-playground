# 🍪 Deep dive: JVM diagnostics (`playground debug` + `playground analyze`)

The commands for "the connector is stuck", "it's slow", "it runs out of memory", "the network drops something":
`playground debug` **collects** what the JVM or the network can tell (thread dumps, a heap dump, a flight recording, a
packet capture), `playground analyze` **reads** it and prints a digest with findings, plus an HTML report. Most
analyzers can also collect for you on a running example, read files a customer sent, or run on shipped samples.
This page is about picking the right tool for a symptom, what each one does to the JVM, and where the files land.
Takes about 15 minutes to read and run.

> [!TIP]
> The video sessions show each analyzer on its own:
> [🧵 A connector looks stuck: analyze thread dumps](/sessions?id=🧵-a-connector-looks-stuck-analyze-thread-dumps),
> [♻️ Long GC pauses or a memory leak: analyze GC logs](/sessions?id=♻️-long-gc-pauses-or-a-memory-leak-analyze-gc-logs) and
> [🛩️ A slow connector: where does the task time go?](/sessions?id=🛩️-a-slow-connector-where-does-the-task-time-go).
> This page goes further: which one to reach for, what they cost the JVM, their gotchas, a hands-on lab and recipes for
> support repros.

| Symptom | Collect | Analyze |
| --- | --- | --- |
| stuck, hanging, deadlock, 100% CPU on a thread | (included) | `playground analyze thread-dump -c connect` (3 dumps 5 s apart) |
| a customer sent `jstack` / `kill -3` output | — | `playground analyze thread-dump -f dump1.txt -f dump2.txt` |
| long pauses, `Full GC`, heap that only grows | (GC logging is on in the playground) | `playground analyze gc-logs -c connect` / `-f <gc.log or folder>` |
| slow: where does the time of the tasks go (I/O, Kafka, locks, converters) | (included) | `playground analyze flight-recorder -c connect --duration 60s --connector <c>` |
| the same, for an open-ended window | `playground debug flight-recorder --action start` … `--action stop` | analyzed on `stop` |
| `OutOfMemoryError`, what fills the heap | `playground debug heap-dump -c connect` | `playground analyze heap-dump -f <.hprof>` (Eclipse MAT, slow) |
| what really goes over the wire | `playground debug tcp-dump -c connect --port 9092 --duration 30` | Wireshark |
| step through the code | `playground debug enable-remote-debugging -c connect` (see the 🐞 session) | your IDE |

---

## 1. Mental model (the 3 things to remember)

1. **Collectors take, analyzers read, and three analyzers do both.** `analyze thread-dump`, `analyze gc-logs` and
   `analyze flight-recorder` accept one input among three:

   | Input | Where the data comes from |
   | --- | --- |
   | `-c <container>` (default `connect` for threads and JFR) | collected now, from the running example |
   | `-f <file>` (repeatable, folders accepted for GC logs) | a file: yours, a customer's, a support bundle |
   | `--sample <name>` | shipped in `tools/` or `gc-analysis/samples`: to see what a command reports, no environment needed |

   `analyze heap-dump` only reads files (`-f` or `--sample`): take the dump with `debug heap-dump` first. Only one of
   the three inputs at a time (`❌ Provide only one of --file, --container and --sample`).

2. **Each collector costs the JVM something different.**

   | Collector | How | What the JVM feels | Size |
   | --- | --- | --- | --- |
   | thread dump (default) | `kill -3`: the JVM prints the dump **to its own stdout**, read back from the container logs | a safepoint pause of milliseconds; no JDK needed in the image; the dumps stay in the container log | ~60 KB per dump on a FileStream worker (more threads, more KB) |
   | thread dump `--jstack` | `jstack -l` in the container | same pause, plus the owners of `java.util.concurrent` locks; **needs a JDK** (the `cp-*` images have a JRE) | same |
   | GC logs | already written: the playground environments start every JVM with `-loggc` (`/var/log/kafka/<name>-gc.log`) | nothing: they are copied with their rotated files | a few MB |
   | flight recorder | a JFR recording driven **over JMX** (`FlightRecorderMXBean`, port `KAFKA_JMX_PORT`), settings `tools/jfr-analyzer/playground.jfc` | low overhead while it records (JFR is built for production), no restart, no jcmd needed | ~200 KB for 20 s on a lightly loaded worker, more under load |
   | heap dump | `jmap -dump` (`-dump:live` with `--live`) in the container | **stops the JVM** while it writes, seconds to minutes; `--live` forces a full GC first | about the used heap |
   | tcp dump | `tcpdump` as root in the container, installed if missing | nothing for the JVM; needs package repositories reachable | depends on traffic |

   On Docker, **a missing JDK tool can restart the container**: `debug heap-dump` installs JDK 17 with
   `container change-jdk` when `jmap` is missing, and `change-jdk` restarts the container, so the state you wanted to
   look at is gone. `debug thread-dump --jstack` refuses instead (`❌ jstack is not installed in container connect (the
   image has a JRE only)`). On CFK, a debug container with a JDK is attached to the pod instead: no restart.

3. **Files land in different places: pass `--output-dir`.**

   | Command | Default location |
   | --- | --- |
   | `debug thread-dump` | `/tmp/thread-dump-<container>-<date>.log`, then opened in your editor |
   | `debug heap-dump` | `./heap-dump-<container>-<date>.hprof` (current folder); `--histo`: `/tmp/heap-dump-<container>-histo-<date>.txt` |
   | `debug flight-recorder --action stop` | `--output-dir`, default `.` |
   | `debug tcp-dump` | `./tcp-dump-<container>-<port>-<date>.pcap` |
   | `analyze thread-dump` | `--output-dir`, default `./thread-analysis-output` (dumps taken with `-c` and the HTML report) |
   | `analyze gc-logs` | `--output-dir`, default `./gc-analysis-output` (logs copied with `-c` and the HTML report) |
   | `analyze flight-recorder` | `--output-dir`, default `./jfr-analysis-output` (recording, `.digest.json`, HTML report) |
   | `analyze heap-dump` | `--output-dir`, default `./heap-analysis` (`summary.txt`, MAT reports, `mat.log`) |

   Running from the repository leaves these folders in it: use `--output-dir /tmp/<something>`. The HTML report is
   opened in the browser only in an interactive terminal; otherwise its `file://` path is printed.

---

## 2. Thread dumps: stuck, hung, deadlocked

```bash
# 3 dumps 5 s apart from connect, then the analysis (the usual first step)
playground analyze thread-dump -c connect --output-dir /tmp/threads
playground analyze thread-dump -c connect --count 5 --interval 10 --output-dir /tmp/threads

# dumps from a customer: one -f per dump of the same JVM (or one file holding several)
playground analyze thread-dump -f dump-1.txt -f dump-2.txt -f dump-3.txt --output-dir /tmp/threads

# one dump to read yourself, in your editor
playground debug thread-dump -c connect
```

What the analysis reports: thread states and pools, deadlocks, locks with their owner and waiters, the most common
stacks, and with several dumps of the same JVM, the threads stuck on the same frames, the CPU each thread used between
dumps, and growing thread pools (Kafka / Connect aware: task threads, herder, request handlers).

Gotchas:

- **One dump says little, three say a lot**: a thread on the same frame in every dump is really blocked; a thread
  that moves is just busy. That's why `analyze thread-dump -c` takes 3 by default.
- **The dumps also land in the container log** (`kill -3` prints them on stdout): `container logs --errors` is not
  affected, but a raw `--tail` right after shows them.
- `debug thread-dump` opens the file with `playground config get editor` (skipped on CI): in a script, prefer
  `analyze thread-dump -c`, which writes to `--output-dir` and returns.
- `--json` prints the analysis as JSON on stdout and the logs on stderr, so it pipes to `jq` even with `-c` (no HTML
  report then).
- Exit code: 0 when the analysis completed, **2 when no thread dump was found** in the input.

---

## 3. GC logs: pauses and leaks

```bash
# the GC log of a running container, with its rotated files
playground analyze gc-logs -c connect --output-dir /tmp/gc
playground analyze gc-logs -c broker --output-dir /tmp/gc

# a customer's logs: every rotated file, or their folder
playground analyze gc-logs -f ./bundle/kafka/ --output-dir /tmp/gc
playground analyze gc-logs -f kafkaServer-gc.log -f kafkaServer-gc.log.0 --run 2   # the log spans restarts
```

What the analysis reports: pause statistics and the longest pauses, Full GC and evacuation / concurrent mode
failures, live set and heap floor trend (a floor that keeps rising is a leak), allocation stalls, GC causes, and
recommendations compared with Kafka's own G1 settings. JDK 7 to 21+, every collector, legacy and unified formats.

Gotchas:

- **The GC log must exist before the problem**: you can't turn it on after the fact. The playground environments
  pass `-loggc` to ZooKeeper, brokers, controllers, Schema Registry and Connect. A container started without it (an
  example that overrides `EXTRA_ARGS`) gets `❌ Could not locate a GC log in container` with the `KAFKA_OPTS` to set
  (`container set-environment-variables`, which recreates the container).
- A log that spans several JVM runs is split by restart, and the **latest run** is analyzed: `--run <n>` for another
  (see the "JVM runs" table of the output).
- Exit code: 0 when the analysis completed, **2 when no GC event was found** (wrong file, or GC logging off).

---

## 4. Flight recorder: where the time goes

```bash
# record connect for 60 s over JMX, then analyze the task threads of one connector
playground analyze flight-recorder -c connect --duration 60s --connector my-sink --output-dir /tmp/jfr

# an open-ended window: start, reproduce, stop (the .jfr is analyzed on stop, --no-analyze to skip)
playground debug flight-recorder -c connect --action start
playground debug flight-recorder -c connect --action status
playground debug flight-recorder -c connect --action stop --output-dir /tmp/jfr

# a recording a customer took, or the shipped sample
playground analyze flight-recorder -f recording.jfr --connector-class io.confluent.connect.jdbc.JdbcSinkConnector --output-dir /tmp/jfr
playground analyze flight-recorder --sample jdbc_postgres_sink --output-dir /tmp/jfr
```

What the analysis reports, for the task threads (`^task-thread-`, or those of `--connector`): how their time splits
between running, socket / file I/O, Kafka client, locks and parking, the hot methods, converters and transforms, with
findings. The text digest has the sections `Findings`, `Task thread time, by state`, `CPU of the task threads, by
layer`, `Hot methods`, then a `Checked and normal:` line (network I/O, lock contention, allocation rate…).

Gotchas:

- **No JMX port, no live recording**: `-c` needs `KAFKA_JMX_PORT` (or `SCHEMA_REGISTRY_JMX_PORT`…) on the container, as
  in the playground environments. `debug flight-recorder` falls back to `jcmd` when the image has one (CFK pods).
- **A recording of an idle connector says nothing**: produce data (or run `playground connector benchmark`) during the
  window.
- `debug flight-recorder --action start` keeps the recording id in `playground.ini` (`flight_recorder.<container>`): a
  restart of the container in between makes `stop` fail (`the JVM restarted, or the recording was closed`).
- `--settings` of `debug flight-recorder`: `playground` (default, the events the analyzer reads), `profile`, `default`
  (JDK settings) or `all` (every event, no threshold: for JDK Mission Control, heavy).
- `--json`: the analysis on stdout, logs on stderr. Exit code: 0 when the analysis completed, **2 when the file is not
  a flight recording** or has no event.

---

## 5. Heap dumps and tcp dumps: the heavy ones

```bash
# the class histogram only: fast, small, often enough to name the culprit
playground debug heap-dump -c connect --histo

# a full dump, then Eclipse MAT in Docker (leak suspects, dominator tree, top components)
playground debug heap-dump -c connect
playground analyze heap-dump -f heap-dump-connect-<date>.hprof --output-dir /tmp/heap
playground analyze heap-dump --sample leak_growth --output-dir /tmp/heap      # two dumps compared

# 30 s of traffic of connect on port 9092, for Wireshark
playground debug tcp-dump -c connect --port 9092 --duration 30
```

Gotchas:

- **Try `--histo` first**: a small text file and a short pause, and the top of the list (`byte[]`, a connector class with
  millions of instances) often answers the question without a multi-GB `.hprof`.
- **A full dump pauses the JVM** for as long as it takes to write the used heap, and needs that much disk in the
  container then on your machine. `--live` forces a full GC first (only reachable objects: smaller, but the garbage
  you may be chasing is gone).
- `analyze heap-dump` builds an Eclipse MAT image on the first run (~100 MB download), then gives MAT 80% of the
  Docker memory (`--max-memory 8g` to change it): a dump bigger than that fails to parse (non-zero exit, `mat.log`).
  The digest is in `<output-dir>/summary.txt`, the MAT reports in `<output-dir>/*/index.html`. No `--json`.
- `tcp-dump` sees the TLS handshake and the failures on an encrypted listener, not the records. It opens Wireshark
  when it's installed.

---

## 6. Hands-on lab (≈15 min)

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh
mkdir -p /tmp/jvm-lab
```

**Step 1: the samples, no environment needed**

```bash
playground analyze thread-dump --sample deadlock_jdk21 --output-dir /tmp/jvm-lab/threads
# … a deadlock section naming the threads ("deadlock-1", "deadlock-2") and the locks they hold
# ✅ HTML report saved: /tmp/jvm-lab/threads/jdk21-scenario-1-thread-report.html
playground analyze gc-logs --sample jdk21_g1_kafka_real --output-dir /tmp/jvm-lab/gc
# ✅ HTML report saved: /tmp/jvm-lab/gc/jdk21_g1_kafka_real-gc-report.html
playground analyze flight-recorder --sample jdbc_postgres_sink --output-dir /tmp/jvm-lab/jfr
# 🛩️  Flight recording of 14 s, 1 task thread(s) …
# ✅ HTML report saved: /tmp/jvm-lab/jfr/jdbc_postgres_sink-jfr-report.html
playground analyze thread-dump -f /etc/hosts --output-dir /tmp/jvm-lab/threads; echo "exit=$?"
# ❌ No thread dump found in hosts. Expected jstack, jcmd Thread.print or kill -3 output …
# exit=2
```

**Step 2: thread dumps of the running worker**

```bash
playground analyze thread-dump -c connect --count 2 --interval 3 --output-dir /tmp/jvm-lab/threads
# 🎯 Taking 2 thread dump(s) of container connect with kill -3, 3 second(s) apart
# ✅ 2 thread dump(s) saved in /tmp/jvm-lab/threads/thread-dumps-connect-20261023-144106.log
# ✅ HTML report saved: /tmp/jvm-lab/threads/thread-dumps-connect-20261023-144106-thread-report.html
playground analyze thread-dump -c connect --count 2 --interval 3 --output-dir /tmp/jvm-lab/threads --json | jq 'keys'
# ["connect_tasks","contention","cpu_interval","cpu_top","deadlocks","dumps","findings","herder","identical_stacks","pools","same_jvm_dumps","stuck"]
playground debug thread-dump -c connect --jstack
# ❌ jstack is not installed in container connect (the image has a JRE only)
# 💡 playground container change-jdk --version 17 installs a JDK, but it RESTARTS the container: …
# ❌ failed to take thread dump on container connect                                     <- exit 1
```

**Step 3: the GC log of the running worker**

```bash
playground analyze gc-logs -c connect --output-dir /tmp/jvm-lab/gc
# 📄 Found GC log: /var/log/kafka/connectDistributed-gc.log
# ✅ 1 GC log file(s) copied to: /tmp/jvm-lab/gc/gc-logs-connect-20261023-144121
# ✅ HTML report saved: /tmp/jvm-lab/gc/gc-logs-connect-20261023-144121-gc-report.html
```

**Step 4: a flight recording while data flows**

```bash
playground topic produce -t filestream --nb-messages -1 --throughput 200 --value '{"id": %g}' > /dev/null 2>&1 &
playground analyze flight-recorder -c connect --duration 20s --connector filestream-sink --output-dir /tmp/jvm-lab/jfr
# 🛩️ recording connect for 20s with the settings of tools/jfr-analyzer/playground.jfc
# ✅ recording saved in /tmp/jvm-lab/jfr/flight-recorder-2026-10-23-14-41-50-connect.jfr
# 🛩️  Flight recording of 20 s, 1 task thread(s)
# Task thread time, by state (mean of the task threads)
#   Kafka client (poll, send)       100%                 <- the FileStream sink waits on poll: nothing slow downstream

playground debug flight-recorder -c connect --action start
# 🛩️ flight recorder is now started on connect over JMX (recording 2, settings playground)
playground debug flight-recorder -c connect --action start
# ❗ 🛩️ flight recorder is already started on connect (settings playground, since 14:41:54): stop it with --action stop
playground debug flight-recorder -c connect --action status
# 🛩️ flight recording running on connect since 2026-10-23 14:41:54 (1s), with jmx, settings playground
playground debug flight-recorder -c connect --action stop --output-dir /tmp/jvm-lab/jfr --no-analyze
# 🛩️ flight recording of connect (13s, settings playground) is available at /tmp/jvm-lab/jfr/flight-recorder-connect-2026-10-23-14-42-05.jfr
kill %1
```

**Optional (slow): a heap histogram, a heap dump, MAT** (not run for this page: the outputs below are described from the
code)

```bash
playground debug heap-dump -c connect --histo
# jmap is not installed on container connect, attempting to install jdk 17        <- the container RESTARTS
# 👻 heap dump is available at /tmp/heap-dump-connect-histo-<date>.txt
playground analyze heap-dump --sample leak --output-dir /tmp/jvm-lab/heap
# 📄 Digest saved in /tmp/jvm-lab/heap/summary.txt
```

```bash
playground stop
```

---

## 7. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "the connector is RUNNING but stuck" | `analyze thread-dump -c connect` (3 dumps), look at the task thread in "stuck on the same frames" |
| "the customer sent a jstack" | `analyze thread-dump -f <each dump>`, then reproduce with the same versions |
| "the worker freezes every few minutes" | `analyze gc-logs -f <their gc logs folder>`: longest pauses, Full GC causes, heap floor trend |
| "throughput dropped after the upgrade" | `analyze flight-recorder -c connect --duration 60s --connector <c>` on both versions (or `connector benchmark --connector-tag A --connector-tag B`, which records the same way) |
| "OutOfMemoryError in the task" | `debug heap-dump --histo` while it grows, then a full dump + `analyze heap-dump` (`--compare` two dumps for the growth) |
| "the database / SaaS closes the connection" | `debug tcp-dump -c connect --port <port> --duration 60` while it happens |
| "a lock between two tasks" | `analyze thread-dump`: the locks section names the owner and the waiters; `debug thread-dump --jstack` on CFK adds `java.util.concurrent` owners |

In a repro model, collect into `/tmp` and print the digest, so the run log shows the finding:

```bash
playground analyze thread-dump -c connect --output-dir /tmp/repro-threads
playground analyze gc-logs -c connect --output-dir /tmp/repro-gc
```

---

## 8. Cheat sheet

```bash
playground analyze thread-dump    [-c <c> [--count 3] [--interval 5] | -f <dump>… | --sample deadlock_jdk21|deadlock_jdk8|healthy_connect] [--json] [--top 10] [--output-dir <d>]
playground analyze gc-logs        [-c <c> | -f <log|folder>… | --sample <name>] [--run <n>] [--json] [--top-pauses 10] [--output-dir <d>]
playground analyze flight-recorder [-c <c> [--duration 60s] | -f <.jfr|.digest.json>… | --sample jdbc_postgres_sink] [--connector <c>] [--threads <regex>] [--json] [--output-dir <d>]
playground analyze heap-dump      -f <.hprof[.gz]> | --sample leak|leak_growth [--compare <.hprof>] [--report-type all|leaks|overview|top-components] [--max-memory 8g] [--output-dir <d>]
playground debug thread-dump      [-c <c>]… [--jstack]
playground debug heap-dump        [-c <c>]… [--live] [--histo]
playground debug flight-recorder  [-c <c>]… --action start|stop|status [--settings playground|profile|default|all] [--output-dir <d>] [--no-analyze]
playground debug tcp-dump         [-c <c>]… [--port <p>] [--duration 30]
```

- Live (`-c`), offline (`-f`) or `--sample`: one at a time. `analyze heap-dump` is offline only.
- `kill -3` and JMX need no JDK in the image; `jstack` / `jmap` do (and `debug heap-dump` installs one, restarting the container).
- Always `--output-dir /tmp/…`. HTML report opened only in an interactive terminal.
- Exit 2 = nothing to analyze in the input (thread-dump, gc-logs, flight-recorder). `--json` everywhere but heap-dump.
- Sources: [`commands/debug/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/debug),
  [`commands/analyze/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/analyze),
  `take_thread_dumps_with_kill_quit` in [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh),
  analyzers in [`tools/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/tools) and
  [`gc-analysis/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/gc-analysis).

---

**Links**

- 🎬 Video sessions: [🧵 thread dumps](/sessions?id=🧵-a-connector-looks-stuck-analyze-thread-dumps),
  [♻️ GC logs](/sessions?id=♻️-long-gc-pauses-or-a-memory-leak-analyze-gc-logs),
  [🛩️ flight recorder](/sessions?id=🛩️-a-slow-connector-where-does-the-task-time-go),
  [🐞 remote debugging](/sessions?id=🐞-a-breakpoint-in-a-running-connector-remote-debugging)
- 📖 [Analyze what you collected](/reusables?id=🔎-analyze-what-you-collected) in the Reproduction toolkit
- 🍪 Deep dives: [`container logs` and `analyze logs`](/deep-dive-container-logs.md) (the same digest for logs),
  [containers](/deep-dive-container-lifecycle.md) (`change-jdk`, `set-environment-variables`)
- 🧠 CLI reference: [playground analyze](/playground%20analyze), [playground debug](/playground%20debug)
