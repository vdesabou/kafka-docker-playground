# jfr-analyzer

Flight recording analyzer behind `playground analyze flight-recorder` and the "Where the time goes" section of
`playground connector benchmark`. It answers one question: **where does the time of the connector tasks go?**

## How it works

| File | Role |
| --- | --- |
| `JfrDigest.java` | Reads `.jfr` files with the JDK flight recorder API (`jdk.jfr.consumer`) and prints a small json digest: per-thread CPU, socket / file / lock / park time, execution and native samples, allocation, GC, exceptions. Runs with the source launcher of a JDK in a `eclipse-temurin:25-jdk` container (the cp images only ship a JRE), and reads recordings of JDK 11+ JVMs. No classification: frames are printed as `package.Class.method`. |
| `jfr_analyzer.py` | Turns one or more digests (one per connect worker) into the analysis: states, CPU by layer, hot methods, findings. Standard library only, runs with the host `python3`. Prints a text report, `--json`, a standalone HTML report, and provides `render_section()` / `render_comparison()` to `tools/benchmark-report/benchmark_report.py`. |
| `playground.jfc` | Settings of the recordings made by the playground (benchmark, `--container`): only the events the analyzer reads. Sent inline over JMX with `FlightRecorderMXBean.setConfiguration`, so its attributes are single-quoted. |
| `samples/*.digest.json` | Digests of real recordings, for `--sample` (no Docker needed). They also carry the connector class, type and mode of their benchmark. |

The recordings are driven over JMX (`jdk.management.jfr:type=FlightRecorder`, with the jmxterm the benchmark already
uses): `newRecording`, `setConfiguration`, `startRecording`, then `stopRecording`, `copyTo`, `closeRecording`. No
`jcmd` (not in the cp images), no restart, no JVM flag: a recording only covers the measure.

## What it reports

Only for the selected threads: `task-thread-<connector>-<n>` (`--connector`), any `--threads` regex, or every
`task-thread-*`. Without a matching thread, every thread of the JVM is analyzed.

| Section | Content | Events |
| --- | --- | --- |
| Task thread time, by state | Share of the recording each task thread spent running, blocked on network I/O, in the Kafka client, on locks, waiting, on file I/O | `jdk.ThreadCPULoad`, `jdk.SocketRead` / `SocketWrite`, `jdk.JavaMonitorEnter`, `jdk.ThreadPark`, `jdk.JavaMonitorWait`, `jdk.ThreadSleep`, `jdk.FileRead` / `FileWrite`, `jdk.NativeMethodSample` |
| CPU by layer | Execution samples, each classified by its first frame outside the JDK: connector, converters (serialization), SMTs, Kafka client, connect framework, libraries (drivers, SDKs), logging, JDK | `jdk.ExecutionSample` |
| Hot methods | First frame outside the JDK of the samples, the JDK method running in it, and a link to the source when the plugin manifest has a GitHub `source_url` | `jdk.ExecutionSample` |
| Network I/O | Calls of 1 ms or more by remote host, and the shorter calls seen by the native samples | `jdk.SocketRead` / `SocketWrite`, `jdk.NativeMethodSample` |
| Allocation | By class and site, MB/s | `jdk.ObjectAllocationSample` |
| Locks and waits | By site | `jdk.JavaMonitorEnter`, `jdk.ThreadPark`, `jdk.JavaMonitorWait`, `jdk.ThreadSleep` |
| Busiest threads | CPU cores per thread, the whole JVM | `jdk.ThreadCPULoad` |
| Findings | One sentence, a number, a next step: the tasks wait on a remote system, on Kafka (consumer fetch or producer), on a lock, sleep; CPU bound; conversion / logging / SMTs take the CPU; JIT warm-up; high allocation; exceptions; GC pauses | all of the above |

How the time of a thread is split:

- running: its CPU load (`jdk.ThreadCPULoad`, summed over the rounds of the recording, times the cpus of the JVM)
- blocked, locks, waiting, file I/O: the sum of the durations of the events, which `playground.jfc` records from 1 ms
  without throttle (the JDK 25 `profile` settings throttle the socket events to 300 per second)
- the rest is split by the native samples of the thread: a consumer poll waiting in `epoll` is Kafka client time, a
  Postgres driver reading its socket is network I/O (counted for the remote when the thread talks to one system only)
- what is left is "not attributed"

A recording made with the JDK `default` or `profile` settings works too, with fewer details: thresholds of 10 or
20 ms, throttled socket events, thread CPU every 10 s.

Exit codes: `0` analysis done, `2` not a flight recording or no event.

## Usage

Always go through the playground CLI:

```bash
playground analyze flight-recorder --sample jdbc_postgres_sink            # try it on the sample
playground analyze flight-recorder                                        # record connect for 60 s over JMX, then analyze
playground analyze flight-recorder -c connect --duration 2m --connector my-sink
playground analyze flight-recorder -f recording.jfr                       # any .jfr (JMC, jcmd, playground debug flight-recorder)
playground analyze flight-recorder -f worker1.jfr -f worker2.jfr          # several workers over the same period
playground analyze flight-recorder -f recording.jfr --threads '^pool-' --json

playground connector benchmark                                            # records the measure by default
playground connector benchmark --no-flight-recorder
```

## Samples

| Sample | Recording |
| --- | --- |
| `jdbc_postgres_sink` | Drain of 3M avro records by the JDBC sink 10.9.9 to PostgreSQL, 1 task, CP 8.3.2 (JDK 25), 14 s: the task waits on Postgres (short round trips), and its CPU goes to Avro conversion |

To add one: run a benchmark, then
`jq -c '. + {connector_class: "<class>", connector_type: "sink|source", mode: "drain|steady", files: ["<name>.jfr"]}' <run>-connect.digest.json > samples/<name>.digest.json`,
and add `<name>` to the allowed values of `--sample` in `scripts/cli/src/bashly.yml`.
