# thread-analyzer

Thread dump analyzer behind `playground analyze thread-dump`. Standard library only, runs with the host
`python3` (3.9+), like `gc-analysis/`.

## What it reads

- `jstack [-l]`, `jcmd <pid> Thread.print` and `kill -3` output, JDK 8 to 25.
- Several dumps per file (repeated `kill -3` in a log), several files, folders, `.gz`.
- Container / application logs: lines interleaved with the dump are ignored.

Dumps are ordered by the timestamp printed before `Full thread dump`, then grouped by JVM (30% of the threads with the
same name and native id, and the same thread numbers `#12` and JVM version: 2 containers can share native ids). Each JVM
is analyzed apart, its dumps compared with each other: the dumps of 2 Connect workers given together give 2 analyses
(`🖥️ JVM 1 of 2: <files>` in the terminal, `{"jvms": [...]}` with `--json`, one HTML report per JVM: `<report>.html`,
`<report>-jvm-2.html`). The output of a single JVM is unchanged.

## What it reports

| Section | Content |
| --- | --- |
| Threads per dump | states (RUNNABLE / BLOCKED / WAITING / TIMED_WAITING / VM threads) |
| Findings | deadlocks, contended locks, lock stalls, threads stuck in a socket write, stuck threads, CPU-hungry threads, growing pools, saturated broker request handlers. Each one is a sentence (`text`, the terminal and `--json`); its title is the words before the first `: `, and a lock stall also has `details` (the waiting thread, the holder, why neither progresses), shown one per line in the HTML reports |
| Deadlocks | cycles in the wait-for graph (monitors and `java.util.concurrent` locks), plus the JVM's own report |
| Lock contention | each lock with its waiters and its owner (state and top application frame) |
| Same frames in all dumps | non-idle threads (BLOCKED, or RUNNABLE outside a poll / accept / select) on the same top 5 frames |
| Lock stalls (`stalls`) | a thread waiting for a lock (monitor, or a `ReentrantLock` / `ReentrantReadWriteLock` it parks to acquire) on the same frames in every dump, whose holder is the same thread on the same frames in every dump: `Lock stall, the same in all N dumps`, even with a single waiter (a lock with 2+ waiters stays a contended lock). Without lock owners in the dump (`jstack` without `-l`), the holder of a `java.util.concurrent` lock is inferred: the thread stuck in socket I/O, using no CPU, in the class that called `lock()`, the closest name first (`most likely held by`); none found: nothing reported (a consumer heartbeat thread waits like that for the lock its `poll()` holds) |
| Stuck in socket I/O (`stuck_io`) | a thread RUNNABLE in a blocking socket write (`socketWrite0`, `NioSocketImpl` / `FileDispatcherImpl.write0`, plain or TLS) on the same frames in every dump with under 5% of a CPU between them (MEDIUM: the peer does not read, or the connection is dead without a reset). A socket read is only reported as the holder of a stalled lock: an idle connection waits in a read too; `epollWait` / `select` threads are idle |
| CPU | per-thread CPU between the first and last dump (`cpu=` / `elapsed=`, JDK 11+), or since thread start |
| Kafka Connect | `task-thread-<connector>-<n>` threads (idle / busy / stuck) and the `DistributedHerder` thread |
| Kafka broker | busy `data-plane-kafka-request-handler-*` threads per dump |
| Pools | threads grouped by name with digits replaced by `#`, and their count across dumps |
| Most common stacks | identical stacks (state + top 8 frames) |

Exit codes: `0` analysis done, `2` no thread dump found, `1` usage error.

## Usage

Always go through the playground CLI:

```bash
playground analyze thread-dump --sample deadlock_jdk21          # try it on the samples below
playground analyze thread-dump                                   # 3 dumps of connect, 5 s apart (kill -3)
playground analyze thread-dump --container broker --count 5 --interval 2
playground analyze thread-dump -f dump1.txt -f dump2.txt -f dump3.txt
playground analyze thread-dump -f ./customer-logs/connect-stdout.log --json
```

Besides the text digest, it writes a self-contained HTML report in `--output-dir` (default
`./thread-analysis-output`), opened in a browser in an interactive terminal (not with `--json`).

With `--container`, the command sends `kill -3` to the JVM (it prints the dump to its stdout, so to the
container logs) and reads the logs back: no JDK is needed in the image. It falls back to `jstack` when the dump
does not reach the logs.

## Samples

`--sample <name>` analyzes them (`--sample` can be repeated):

| `--sample` | File | Content |
| --- | --- | --- |
| `deadlock_jdk21` | `jdk21-scenario-{1,2,3}.txt` | 3 `jstack -l` dumps of `TdLoad` on JDK 21, 3 s apart: deadlock, 8 threads blocked on one monitor, a CPU-hot thread, a Connect-like task stuck on a socket read, a leaking pool |
| `deadlock_jdk8` | `jdk8-scenario.txt` | the same scenario on JDK 8 (hex `nid`, no `cpu=`) |
| `healthy_connect` | `cp-8.3.2-connect-kill-3-logs.txt` | 3 `kill -3` dumps of a healthy CP 8.3.2 Connect worker, read from its container logs |
| | `TdLoad.java` | the scenario program |

```bash
python3 tools/thread-analyzer/thread_dump_analyzer.py tools/thread-analyzer/samples/jdk21-scenario-*.txt
```
