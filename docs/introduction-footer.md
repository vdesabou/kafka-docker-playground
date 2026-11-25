## 🏁 Getting started

```bash
# 1. install the playground (macOS, Linux, WSL)
curl -fsSL https://kafka-docker-playground.io/install.sh | bash

# 2. find the example closest to your case
playground find-example "s3 sink"

# 3. run it, with the Confluent Platform version you need
playground run -f connect/connect-aws-s3-sink/s3-sink.sh --tag 8.4.1
```

Prefer menus? `playground run` alone lets you pick the example and its options. All the ways to run (Codespaces, EC2, Podman) and the prerequisites are in **[🚀 How to Use](/how-to-use.md)**; every example, with its README and CI status, is in the **[👾 Examples](/examples.md)** page.

🎬 Want the explanation too? The **[Bite size sessions](/sessions.md)** are 2–3 minute narrated walkthroughs of one command, from the symptom to the HTML report.

## ✨ What you can do

### ▶️ Run

- 🔗 177 self-managed [connector examples](/content?id=🔗-connectors) and 112 [fully managed ones](/content?id=🤖-fully-managed-connectors), plus [Confluent Cloud](/content?id=☁️-confluent-cloud), [commercial features](/content?id=💸-confluent-commercial) (Tiered Storage, Control Center, audit logs…), [Cluster Linking, Replicator and MirrorMaker 2](/content?id=🌍-multi-data-center-deployments) and [other playgrounds](/content?id=👾-other-playgrounds) (ksqlDB, Flink, Schema Registry…)
- 🔐 19 [environments](/content?id=🔐-environments) (SASL, SSL, Kerberos, LDAP, RBAC, OAuth, multi-DC, Ansible), and any self-managed connector example on Kubernetes with `--environment cfk`
- 🎯 Any Confluent Platform or connector [version](/how-to-use?id=🪄-specify-versions), with the third-party accounts of the examples set up and checked for you ([accounts](/how-to-use?id=☁️-accounts-of-the-examples))
- 🌐 Locally with Docker or [Podman](/how-to-use?id=🦭-using-podman-instead-of-docker), in your browser with [GitHub Codespaces](/how-to-use?id=🌐-in-your-browser-github-codespaces), or remotely on [EC2](/playground%20ec2)
- 🗺️ [Start from your area](/areas.md): Connect, brokers and observability, streams and schemas, platform and security

### 🚑 Diagnose

- 🧭 About 300 commands that each answer a support question in one call: [find the right one](/which-command.md) from your own words with `playground find-command`
- 🔌 A connector that fails, is stuck or lags: [connector diagnose](/playground%20connector%20diagnose), [show-lag](/playground%20connector%20show-lag), [flow](/playground%20connector%20flow) (source → topic → sinks), [reconcile](/playground%20connector%20reconcile) (topic vs table)
- 📊 Shareable [reports](/reports.md) for logs, thread and heap dumps, GC logs, flight recordings, network captures, CFK bundles and Oracle XStream reports
- 🐳 [`playground analyze logs` with nothing installed but Docker](/deep-dive-analyze-logs?id=🐳-with-nothing-installed-but-docker), offline: anyone can run it on their own logs, a customer included

### 👷 Reproduce

- 🛠 Turn an example into your own [reproduction model](/toolkit-reproduction-models.md), or chain a source and sinks with the [🔗 pipeline builder](pipeline-builder.html ':ignore')
- 📥 Start from the customer's config as is: [connector create-or-update](/playground%20connector%20create-or-update) reads CFK, Strimzi, terraform and `.properties` files
- 🔀 Find the connector version where a behaviour changed with [repro bisect](/playground%20repro%20bisect), and read the [source code](/playground%20connector-plugin%20sourcecode) or the changelog at the exact version
- 📈 [Benchmark](/toolkit-performance?id=⏱️-benchmark-a-connector) a connector: throughput, version comparison, and where the time of the tasks goes
- 🗄️ Query the databases of the examples with [db sql](/playground%20db%20sql), and check their CDC prerequisites with [db cdc-check](/playground%20db%20cdc-check)

### 🎓 Learn

- 🎬 [Bite size sessions](/sessions.md) (short narrated videos) and 🍪 [deep dives](/deep-dives.md) (mental model, gotchas, a lab replayed nightly by CI, recipes for support repros)
- 🧑‍🎓 [Academy](/academy.md) and 🎓 [how the playground works](/how-it-works.md), CI included
- 🤖 Use it with [Claude Code](/claude-code.md): it picks the right playground commands to find the root cause
- 🎩 On macOS, the kdp [Alfred workflow](/alfred.md) puts examples, plugin versions and running connectors one keystroke away

## 📊 See what it finds

Real reports, generated from the samples shipped in the repository: browse them all in the [reports](/reports) gallery.

<a href="#/reports"><img src="images/reports/thread-dump.png" alt="thread dump report" width="32%"></a>
<a href="#/reports"><img src="images/reports/benchmark.png" alt="connector benchmark report" width="32%"></a>
<a href="#/reports"><img src="images/reports/oracle-xstream-report.png" alt="Oracle XStream report" width="32%"></a>

## 💡 Philosophy

Most examples are deliberately minimal: they let you test components quickly, automatically and with any [version](/how-to-use?id=🪄-specify-versions), and above all [build](/toolkit-reproduction-models.md) your own reproduction models.

## ⭐️ Support my work

Love it? Give it a ⭐️ by clicking below:

<a href="https://github.com/vdesabou/kafka-docker-playground/stargazers"><img src="https://img.shields.io/github/stars/vdesabou/kafka-docker-playground?style=social" style="margin-left:0;box-shadow:none;border-radius:0;height:24px"></a>