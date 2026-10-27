# 🍪 Deep dives

Written pages that go deep into one family of `playground` commands: the mental model, what runs under the hood, the
gotchas, a hands-on lab you can run in about 10 minutes, and recipes for reproducing support cases. When a
[🎬 Bite size session](/sessions.md) covers the same commands, watch the video for the overview and read the deep dive
to master them. Every output shown in a lab comes from a real run, and CI replays the labs every night
([`other/deep-dive-labs`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/deep-dive-labs)): a
CLI change that makes a page wrong shows up as a failing test.

> [!TIP]
> Each deep dive follows the same outline, so you can jump to the part you need: mental model first, then the commands
> with their gotchas, a hands-on lab, recipes for support repros, and a cheat sheet at the end.

## 🧩 Connectors

### 🔌 Deploy a connector: create, update, wait, validate, diff

- 📖 [Read the deep dive](/deep-dive-connector-create-or-update.md)
- 🧠 Commands: `connector create-or-update`, `wait`, `validate`, `diff`, `status`, `show-config`
- 🎬 Bite size session: [🔌 The sink fails right after it is deployed](/sessions?id=🔌-the-sink-fails-right-after-it-is-deployed)

### 🩺 A connector doesn't work: diagnose and the dead letter queue

- 📖 [Read the deep dive](/deep-dive-connector-troubleshooting.md)
- 🧠 Commands: `connector diagnose`, `topic dlq inspect`, `topic dlq replay`
- 🎬 Bite size session: [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)

### 🧭 Offsets and lag: sinks, sources, consumer groups

- 📖 [Read the deep dive](/deep-dive-offsets-and-lag.md)
- 🧠 Commands: `connector show-lag`, `connector offsets`, `consumer-group`
- 🎬 Bite size session: [⏪ The lag of a sink is stuck](/sessions?id=⏪-the-lag-of-a-sink-is-stuck)

### 🔀 Test a transform chain on a record

- 📖 [Read the deep dive](/deep-dive-connector-smt-test.md)
- 🧠 Commands: `connector smt test`
- 🎬 Bite size session: [🔀 What does this transform chain do to a record?](/sessions?id=🔀-what-does-this-transform-chain-do-to-a-record)

### 🧑‍💻 Connector plugins: versions, config keys, source code, jars

- 📖 [Read the deep dive](/deep-dive-connector-plugin.md)
- 🧠 Commands: `connector-plugin versions`, `config-key`, `sourcecode`, `search-jar`
- 🎬 Bite size session: [🧑‍💻 The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version)

### 📈 Benchmark a connector

- 📖 [Read the deep dive](/deep-dive-connector-benchmark.md)
- 🧠 Commands: `connector benchmark`
- 🎬 Bite size session: [📈 Is version Y slower?](/sessions?id=📈-is-version-y-slower-benchmark-two-versions)

### 🌤️ Fully managed connectors (Confluent Cloud)

- 📖 [Read the deep dive](/deep-dive-fully-managed.md)
- 🧠 Commands: `connector create-or-update`, `status`, `offsets`… on Confluent Cloud
- 🎬 Bite size session: [🚚 Move to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed), [🏗️ Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform)

## 🗃️ Topics and schemas

### 📨 Produce test data: schemas, payloads, keys, load

- 📖 [Read the deep dive](/deep-dive-topic-produce.md)
- 🧠 Commands: `topic produce`
- 🎬 Bite size session: [📨 Produce realistic test data](/sessions?id=📨-produce-realistic-test-data)

### 📥 Read a topic: deserializers, positioning, assertions

- 📖 [Read the deep dive](/deep-dive-topic-consume.md)
- 🧠 Commands: `topic consume`
- 🎬 Bite size session: [📥 Read a topic](/sessions?id=📥-read-a-topic)

### 🗂️ Topic administration: create, alter, counts, waiting

- 📖 [Read the deep dive](/deep-dive-topic-administration.md)
- 🧠 Commands: `topic create`, `alter`, `describe`, `list`, `get-number-records`, `get-offsets`, `wait-for-records`, `delete`
- 🎬 Bite size session: [🪛 A producer gets RecordTooLargeException](/sessions?id=🪛-a-producer-gets-recordtoolargeexception)

### 🔰 Schema Registry: subjects, ids, compatibility, deletion

- 📖 [Read the deep dive](/deep-dive-schema.md)
- 🧠 Commands: `schema get`, `register`, `set-compatibility`, `delete`, `derive-schema`
- 🎬 Bite size session: [🔰 Schema not found after a cleanup](/sessions?id=🔰-schema-not-found-after-a-cleanup)

## 🔍 Logs and JVM diagnostics

### 📜 Read logs: live digest, waiting for a line, customer bundles

- 📖 [Read the deep dive](/deep-dive-container-logs.md)
- 🧠 Commands: `container logs`, `analyze logs`
- 🎬 Bite size session: [🕵️ A connector failed: read the logs](/sessions?id=🕵️-a-connector-failed-read-the-logs-live-or-from-a-customer-bundle)

### 🔊 Log levels: TRACE without a restart

- 📖 [Read the deep dive](/deep-dive-log-levels.md)
- 🧠 Commands: `debug log-level`, `connector log-level`
- 🎬 Bite size session: [🧬 TRACE on a running connector](/sessions?id=🧬-trace-on-a-running-connector-without-a-restart)

### 🧵 JVM diagnostics: which collector, which analyzer

- 📖 [Read the deep dive](/deep-dive-jvm-diagnostics.md)
- 🧠 Commands: `debug thread-dump`, `heap-dump`, `flight-recorder`, `jscissors`, `analyze thread-dump`, `gc-logs`, `flight-recorder`, `heap-dump`, `jscissors`
- 🎬 Bite size session: [🧵 thread dumps](/sessions?id=🧵-a-connector-looks-stuck-analyze-thread-dumps), [♻️ GC logs](/sessions?id=♻️-long-gc-pauses-or-a-memory-leak-analyze-gc-logs), [🛩️ flight recorder](/sessions?id=🛩️-a-slow-connector-where-does-the-task-time-go), [✂️ jscissors](/sessions?id=✂️-records-vanish-a-task-hangs-what-does-the-code-do)

## ⚙️ Run, environments and reproductions

### 🕹️ Running examples and changing versions

- 📖 [Read the deep dive](/deep-dive-run-and-versions.md)
- 🧠 Commands: `run`, `re-run`, `update-version`, `history`
- 🎬 Bite size session: [🕹️ Run an example](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags), [🎯 Is it fixed in a newer version?](/sessions?id=🎯-is-it-fixed-in-a-newer-version)

### 🐳 Containers: exec, cp, restart vs recreate, environment, JDK

- 📖 [Read the deep dive](/deep-dive-container-lifecycle.md)
- 🧠 Commands: `container exec`, `cp`, `restart`, `recreate`, `set-environment-variables`, `change-jdk`, `status`
- 🎬 Bite size session: [🐳 Restart or recreate?](/sessions?id=🐳-restart-or-recreate-what-a-container-keeps)

### 🔐 Secured environments: SASL, SSL, Kerberos, RBAC

- 📖 [Read the deep dive](/deep-dive-secured-environments.md)
- 🧠 Commands: `start-environment --environment …`, `run --environment …`, `rbac role-binding`
- 🎬 Bite size session: [🔐 The same example under SASL_SSL and RBAC](/sessions?id=🔐-the-same-example-under-sasl_ssl-and-rbac)

### 🐌 A slow or broken network, on purpose

- 📖 [Read the deep dive](/deep-dive-network-traffic.md)
- 🧠 Commands: `debug block-traffic`, `debug degrade-traffic`
- 🎬 Bite size session: [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose)

### 🛠 Reproduction models: bootstrap, check, export, import

- 📖 [Read the deep dive](/deep-dive-reproduction-models.md)
- 🧠 Commands: `repro bootstrap`, `repro check`, `repro export`, `repro import`
- 🎬 Bite size session: [🧪 The life of a reproduction model](/sessions?id=🧪-the-life-of-a-reproduction-model)

### 🔑 Credentials and the 1Password setup

- 📖 [Read the deep dive](/deep-dive-secrets.md)
- 🧠 Commands: `secrets check`, `set`, `import`, `list`, `link`, `backend`, `profile`, `env`, `scan`
- 🎬 Bite size session: [🕹️ Run an example](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) (`secrets set`)
