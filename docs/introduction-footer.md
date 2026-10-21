## ✨ Features

- 🔗 150+ onprem (or self-managed) connectors [examples](/content?id=🔗-connectors) (Docker Compose and CFK environments supported)
- 🌤️ 100+ fully-managed connectors [examples](/content?id=%f0%9f%a4%96-fully-managed-connectors)
- 🔐 10+ secured [environments](/content?id=%F0%9F%94%90-environments) (SASL, RBAC, SSL...)
- ☁️ Confluent Cloud [examples](/content?id=☁%EF%B8%8F-confluent-cloud)
- 💸 Confluent commercial [features](/content?id=💸-confluent-commercial) (Tiered Storage, Control Center, Audit logs...)
- ♻️ Cluster Linking, Replicator and MirrorMaker 2 [examples](/content?id=🌍-multi-data-center-deployments)
- 🎯 Run examples with any Confluent Platform or connector [versions](/how-to-use?id=🪄-specify-versions)
- 🧠 Easily run commands with playground [CLI](/cli)
- 📈 [Benchmark](/reusables?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector) a connector: throughput, version comparison, and where the time of the tasks goes (Java Flight Recorder)
- 📊 Find what is wrong with shareable [reports](/reports): thread dumps, GC logs, flight recordings, connector benchmarks, SMT tests, Oracle XStream and CFK diagnostics
- 🎓 Learn how the playground [works](/how-it-works)
- 🧰 Build your own reproduction models with the [reproduction toolkit](/reusables)
- 🎩 Work remotely with VS Code on AWS EC2 instances using [playground ec2](/playground%20ec2) commands
- 🤖 Automated testing using Github Actions [CI](/how-it-works?id=🤖-how-ci-works)
- 👾 And even more [playgrounds](/content?id=👾-other-playgrounds)...

## 📊 See what it finds

Real reports, generated from the samples shipped in the repository: browse them all in the [reports](/reports) gallery.

<a href="#/reports"><img src="images/reports/thread-dump.png" alt="thread dump report" width="32%"></a>
<a href="#/reports"><img src="images/reports/benchmark.png" alt="connector benchmark report" width="32%"></a>
<a href="#/reports"><img src="images/reports/oracle-xstream-report.png" alt="Oracle XStream report" width="32%"></a>

## 🍿 See it in action

<!-- tabs:start -->

#### **🔎 Find & run**

Find the example closest to your case, then run it with the Confluent Platform and connector versions you need.

<video src="videos/find-example.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🕹️ Run menu**

Prefer menus to flags? `playground run` lets you pick an example and its options (versions, environment, connector zip...), and shows the matching command.

<video src="videos/run-menu.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🔐 Secrets**

[Check](/playground%20secrets%20check) which credentials an example needs, and [store](/playground%20secrets%20set) them once for all your runs.

<video src="videos/secrets.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **📨 Topics**

[Produce](/playground%20topic%20produce) realistic records from a schema (Avro, JSON Schema, Protobuf or plain JSON) and [consume](/playground%20topic%20consume) them back.

<video src="videos/topic.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🩺 Diagnose**

A connector stopped working: status, error digest with the root cause, progress and next steps, in one command.

<video src="videos/diagnose.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🐢 Show lag**

Is the sink catching up, standing still or falling behind? [Watch](/playground%20connector%20show-lag) its consumer lag until it reaches 0.

<video src="videos/show-lag.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **📜 Logs**

Turn on [DEBUG](/playground%20connector%20log-level) for a connector, then [wait for](/playground%20connector%20logs) the log line you are looking for (here the SQL the JDBC sink runs).

<video src="videos/logs.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🧑‍💻 Source code**

Read the [source code](/playground%20connector-plugin%20sourcecode) of a connector at the exact version you run, compare two versions, or check it out locally.

<video src="videos/sourcecode.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **✅ Validate & diff**

A customer sent their config: validate it without creating anything, then see how it differs from the connector of the example.

<video src="videos/validate-diff.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **👷 Repro model**

Turn an example into a reproduction model of your own issue, ready to edit and run.

<video src="videos/repro-bootstrap.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🔗 Pipeline**

Chain a source example and a sink example on the same topic in a single [reproduction model](/reusables).

<video src="videos/repro-pipeline.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **📈 Benchmark**

[Benchmark](/reusables?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector) the throughput of a connector (and compare versions), with a flight recording that says where the time went.

<video src="videos/benchmark.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🔬 Analyze**

Digest thread dumps, GC logs, heap dumps, flight recordings, CFK bundles or Oracle XStream reports (here a thread dump sample).

<video src="videos/analyze.mp4" autoplay loop muted playsinline controls width="100%"></video>

#### **🤖 Claude Code**

Ask [Claude Code](/claude-code) in plain language: it checks the connector with the playground CLI and explains the root cause and the fix.

<video src="videos/claude-code.mp4" autoplay loop muted playsinline controls width="100%"></video>

<!-- tabs:end -->

🎬 Want the explanation too? The **[Bite size sessions](/sessions.md)** are 2–3 minute narrated walkthroughs of one command, from the symptom to the HTML report.

## 🏁 Getting Started

Check out the **[How to Use](/how-to-use.md)** section, then select an example in the **[Content](/content.md)** section and run it !

## 💡 Ideology

Most of the examples in the playground are very basic, but it allows to quickly test components in an automated way (and with any [versions](/how-to-use?id=🪄-specify-versions)) and most importantly to easily [build](/reusables) your own reproduction models !

## ⭐️ Support my work

Love it? Give it a ⭐️ by clicking below:

<a href="https://github.com/vdesabou/kafka-docker-playground/stargazers"><img src="https://img.shields.io/github/stars/vdesabou/kafka-docker-playground?style=social" style="margin-left:0;box-shadow:none;border-radius:0;height:24px"></a>