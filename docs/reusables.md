# 🧰 Reproduction toolkit

Everything you need once an example runs, one page per topic:

| Page | What is in it |
| --- | --- |
| [🛠 Reproduction models](/toolkit-reproduction-models.md) | Bootstrap a reproduction model from an example, share it as a self-contained bundle, and the helper functions to use in its script. |
| [👉 Producing, consuming and SMTs](/toolkit-data.md) | Put data in a topic, read it back, and check what a transform chain does to a record. |
| [🐛 Debugging and analysis](/toolkit-debugging.md) | Attach a debugger, raise the log levels, take dumps and recordings of a JVM or of the network, then analyze what you collected. |
| [🌐 Network](/toolkit-network.md) | Break the network on purpose: block traffic, add latency or packet loss, cut TCP connections, or put an HTTPS proxy in the way. |
| [☁️ Fully managed connectors](/toolkit-fully-managed.md) | Reproduce what customers do with fully managed connectors: a service account with the least ACLs, or Terraform. |
| [♨️ Connectors and JDKs](/toolkit-environment.md) | Add other connector plugins or SMTs to an example, or replace the JDK of a container image. |
| [🏎️ Performance](/toolkit-performance.md) | Measure the throughput and the latency of a connector, compare versions, and keep a database busy while you watch. |

## ⚡ Everyday commands

The commands to know once an example runs, and where to read more about each one:

| You want | Command | Read more |
| --- | --- | --- |
| to check that the container engine is ready | `playground doctor` | [Prerequisites](/how-to-use?id=☑️-prerequisites) |
| to see what is running (example, containers, connectors, topics) | `playground status` | [Containers](/deep-dive-container-lifecycle?id=_2-looking-inside-status-exec-ssh-get-properties-cp) |
| to know which container is failing | `playground container display-error-all` | [The ERROR digest](/deep-dive-container-logs?id=_3-the-error-digest-errors) |
| the errors of one container, de-duplicated | `playground container logs -c connect --errors --since 10m` | [The ERROR digest](/deep-dive-container-logs?id=_3-the-error-digest-errors) |
| to follow, filter or open the logs | `playground container logs -c connect` (`--grep "Caused by" --no-follow`, `--open`) | [Reading live logs](/deep-dive-container-logs?id=_2-reading-live-logs) |
| to wait for a log line instead of a `sleep` | `playground container logs -c connect --wait-for-log "<line>" --max-wait 120` | [Waiting for a log line](/deep-dive-container-logs?id=_5-waiting-for-a-log-line-wait-for-log) |
| to wait for a connector, or for records | `playground connector wait --connector <c>` / `playground topic wait-for-records --topic <t> --min-expected-messages 10` | [Waiting](/deep-dive-connector-create-or-update?id=_3-waiting-wait-no-wait-connector-wait) |
| a shell or a command in a container, files in or out | `playground container ssh\|exec\|cp -c connect` (`--root`) | [Looking inside](/deep-dive-container-lifecycle?id=_2-looking-inside-status-exec-ssh-get-properties-cp) |
| to restart, kill or recreate containers | `playground container restart\|kill\|recreate -c connect` / `kill-all` | [Acting on them](/deep-dive-container-lifecycle?id=_3-acting-on-them-restart-kill-pause-recreate) |
| the number of records, the biggest topics | `playground topic get-number-records --topic <t>` / `playground topic get-size` | [Counting](/deep-dive-topic-administration?id=_4-counting-and-waiting-get-number-records-get-offsets-wait-for-records), [sizes](/deep-dive-topic-administration?id=_3-looking-at-topics-describe-list-get-size) |
| the offsets of a connector, of a consumer group | `playground connector offsets get` / `playground topic display-consumer-offsets` | [Offsets](/deep-dive-offsets-and-lag?id=_3-connector-offsets-get-alter-reset) |

To understand one command family in depth (mental model, gotchas, recipes for support repros), see the [🍪 Deep dives](/deep-dives.md).
