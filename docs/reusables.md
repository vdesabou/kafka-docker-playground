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

To understand one command family in depth (mental model, gotchas, recipes for support repros), see the [🍪 Deep dives](/deep-dives.md).
