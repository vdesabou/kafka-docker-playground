# thread-analyzer

Thread dump analyzer behind `playground debug thread-analyze`. Standard library only, runs with the host
`python3` (3.9+), like `gc-analysis/`.

## What it reads

- `jstack [-l]`, `jcmd <pid> Thread.print` and `kill -3` output, JDK 8 to 25.
- Several dumps per file (repeated `kill -3` in a log), several files, folders, `.gz`.
- Container / application logs: lines interleaved with the dump are ignored.

Dumps are ordered by the timestamp printed before `Full thread dump`. Consecutive dumps of the same JVM (same
thread names and native ids) are compared.

## What it reports

| Section | Content |
| --- | --- |
| Threads per dump | states (RUNNABLE / BLOCKED / WAITING / TIMED_WAITING / VM threads) |
| Findings | deadlocks, contended locks, stuck threads, CPU-hungry threads, growing pools, saturated broker request handlers |
| Deadlocks | cycles in the wait-for graph (monitors and `java.util.concurrent` locks), plus the JVM's own report |
| Lock contention | each lock with its waiters and its owner (state and top application frame) |
| Same frames in all dumps | non-idle threads (BLOCKED, or RUNNABLE outside a poll / accept / select) on the same top 5 frames |
| CPU | per-thread CPU between the first and last dump (`cpu=` / `elapsed=`, JDK 11+), or since thread start |
| Kafka Connect | `task-thread-<connector>-<n>` threads (idle / busy / stuck) and the `DistributedHerder` thread |
| Kafka broker | busy `data-plane-kafka-request-handler-*` threads per dump |
| Pools | threads grouped by name with digits replaced by `#`, and their count across dumps |
| Most common stacks | identical stacks (state + top 8 frames) |

Exit codes: `0` analysis done, `2` no thread dump found, `1` usage error.

## Usage

Always go through the playground CLI:

```bash
playground debug thread-analyze                                   # 3 dumps of connect, 5 s apart (kill -3)
playground debug thread-analyze --container broker --count 5 --interval 2 --html
playground debug thread-analyze -f dump1.txt -f dump2.txt -f dump3.txt --html
playground debug thread-analyze -f ./customer-logs/connect-stdout.log --json
```

With `--container`, the command sends `kill -3` to the JVM (it prints the dump to its stdout, so to the
container logs) and reads the logs back: no JDK is needed in the image. It falls back to `jstack` when the dump
does not reach the logs.

## Samples

| File | Content |
| --- | --- |
| `jdk21-scenario-{1,2,3}.txt` | 3 `jstack -l` dumps of `TdLoad` on JDK 21, 3 s apart: deadlock, 8 threads blocked on one monitor, a CPU-hot thread, a Connect-like task stuck on a socket read, a leaking pool |
| `jdk8-scenario.txt` | the same scenario on JDK 8 (hex `nid`, no `cpu=`) |
| `cp-8.3.2-connect-kill-3-logs.txt` | 3 `kill -3` dumps of a healthy CP 8.3.2 Connect worker, read from its container logs |
| `TdLoad.java` | the scenario program |

```bash
python3 tools/thread-analyzer/thread_dump_analyzer.py tools/thread-analyzer/samples/jdk21-scenario-*.txt
```
