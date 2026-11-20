# Resource faults: OOM kill, cpu limit, broker disk full

## Objective

Showcase [`playground debug resources`](https://kafka-docker-playground.io/#/playground%20debug%20resources): change the cpu and memory limits of a running container (`docker update`, no restart), and fill its disk to a percentage. Here the connect worker is OOM killed by a memory limit below its usage, and a broker stops writing when its log dir is full.

🍪 Deep dive: [JVM diagnostics](https://kafka-docker-playground.io/#/deep-dive-jvm-diagnostics)

## How to run

```bash
playground run -f resource-faults<tab>
```

## What the script does

It starts the plaintext environment, with the log dir of the broker on a tmpfs of 1g (`docker-compose.plaintext.yml`): on Docker Desktop, the data volume is on the disk of Docker itself, shared by every container, and `--fill-disk` refuses to fill it. Then:

1. shows the limits, the usage, the JVM max heap and the disk of connect and broker: `debug resources --container connect --container broker`
2. gives connect half a cpu (`--cpus 0.5`), then 300m of memory (`--memory 300m`, no swap), less than the worker uses: the kernel kills it (OOM kill, exit 137), and the restart policy starts it again, killed again. `debug resources --container connect` reports the OOM kills (from the `oom` events of docker: the `OOMKilled` flag is cleared at each restart)
3. goes back to the original limits (`--reset`) and waits for the REST API of connect
4. fills the log dir of the broker to 100% (`--fill-disk 100%`): the next records cannot be written, the broker logs `java.io.IOException: No space left on device`, marks its log dir offline and stops (its only log dir). `--reset` removes the fill file. The restart policy starts the broker again, with an empty tmpfs: the records of the topics are gone

## Use it in a repro

```bash
# a worker short of memory: GC pressure, then an OOM kill (exit 137)
playground debug resources --container connect --memory 1g

# a starved worker: slow tasks, missed heartbeats, rebalances
playground debug resources --container connect --cpus 0.5

# a disk almost full (needs a filesystem of its own, see docker-compose.plaintext.yml)
playground debug resources --container broker --fill-disk 95%

# the limits, the usage, -Xmx, OOM kills and the disk
playground debug resources --container connect

# back to the original limits, fill file removed
playground debug resources --container connect --container broker --reset
```

❕ The JVM sizes its heap when it starts (`-Xmx`): a memory limit below `-Xmx` plus the off-heap memory gets the container OOM killed rather than an `OutOfMemoryError`. A recreate of the container drops the limits.
