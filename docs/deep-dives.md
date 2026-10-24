# 🍪 Deep dives

Written pages that go deep into one family of `playground` commands: the mental model, what runs under the hood, the
gotchas, a hands-on lab you can run in about 10 minutes, and recipes for reproducing support cases. When a
[🎬 Bite size session](/sessions.md) covers the same commands, watch the video for the overview and read the deep dive
to master them. Every output shown in a lab comes from a real run, and CI replays the labs every night
([`other/deep-dive-labs`](https://github.com/vdesabou/kafka-docker-playground/tree/master/other/deep-dive-labs)): a
CLI change that makes a page wrong shows up as a failing test.

| | Deep dive | Commands | Video session |
| --- | --- | --- | --- |
| 🐌 | [A slow or broken network, on purpose](/deep-dive-network-traffic.md) | `debug block-traffic`, `debug degrade-traffic` | [🐌 A slow or broken network, on purpose](/sessions?id=🐌-a-slow-or-broken-network-on-purpose) |
| 📨 | [Produce test data: schemas, payloads, keys, load](/deep-dive-topic-produce.md) | `topic produce` | [📨 Produce realistic test data](/sessions?id=📨-produce-realistic-test-data) |
| 📥 | [Read a topic: deserializers, positioning, assertions](/deep-dive-topic-consume.md) | `topic consume` | [📥 Read a topic](/sessions?id=📥-read-a-topic) |
| 🔌 | [Deploy a connector: create, update, wait, validate, diff](/deep-dive-connector-create-or-update.md) | `connector create-or-update`, `wait`, `validate`, `diff`, `status`, `show-config` | [🔌 The sink fails right after it is deployed](/sessions?id=🔌-the-sink-fails-right-after-it-is-deployed) |
| 🩺 | [A connector doesn't work: diagnose and the dead letter queue](/deep-dive-connector-troubleshooting.md) | `connector diagnose`, `topic dlq inspect`, `topic dlq replay` | [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing) |
| 📜 | [Read logs: live digest, waiting for a line, customer bundles](/deep-dive-container-logs.md) | `container logs`, `analyze logs` | [🕵️ A connector failed: read the logs](/sessions?id=🕵️-a-connector-failed-read-the-logs-live-or-from-a-customer-bundle) |
| 🧭 | [Offsets and lag: sinks, sources, consumer groups](/deep-dive-offsets-and-lag.md) | `connector show-lag`, `connector offsets`, `consumer-group` | [⏪ The lag of a sink is stuck](/sessions?id=⏪-the-lag-of-a-sink-is-stuck) |
| 🔊 | [Log levels: TRACE without a restart](/deep-dive-log-levels.md) | `debug log-level`, `connector log-level` | [🧬 TRACE on a running connector](/sessions?id=🧬-trace-on-a-running-connector-without-a-restart) |
| 🔀 | [Test a transform chain on a record](/deep-dive-connector-smt-test.md) | `connector smt test` | [🔀 What does this transform chain do to a record?](/sessions?id=🔀-what-does-this-transform-chain-do-to-a-record) |
| 🛠 | [Reproduction models: bootstrap, check, export, import](/deep-dive-reproduction-models.md) | `repro bootstrap`, `repro check`, `repro export`, `repro import` | [🧪 The life of a reproduction model](/sessions?id=🧪-the-life-of-a-reproduction-model) |
| 🐳 | [Containers: exec, cp, restart vs recreate, environment, JDK](/deep-dive-container-lifecycle.md) | `container exec`, `cp`, `restart`, `recreate`, `set-environment-variables`, `change-jdk`, `status` | [🐳 Restart or recreate?](/sessions?id=🐳-restart-or-recreate-what-a-container-keeps) |
| 🧑‍💻 | [Connector plugins: versions, config keys, source code, jars](/deep-dive-connector-plugin.md) | `connector-plugin versions`, `config-key`, `sourcecode`, `search-jar` | [🧑‍💻 The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version) |
| 🔰 | [Schema Registry: subjects, ids, compatibility, deletion](/deep-dive-schema.md) | `schema get`, `register`, `set-compatibility`, `delete`, `derive-schema` | [🔰 Schema not found after a cleanup](/sessions?id=🔰-schema-not-found-after-a-cleanup) |
| 🧵 | [JVM diagnostics: which collector, which analyzer](/deep-dive-jvm-diagnostics.md) | `debug thread-dump`, `heap-dump`, `flight-recorder`, `analyze thread-dump`, `gc-logs`, `flight-recorder`, `heap-dump` | [🧵 thread dumps](/sessions?id=🧵-a-connector-looks-stuck-analyze-thread-dumps), [♻️ GC logs](/sessions?id=♻️-long-gc-pauses-or-a-memory-leak-analyze-gc-logs), [🛩️ flight recorder](/sessions?id=🛩️-a-slow-connector-where-does-the-task-time-go) |
| 🕹️ | [Running examples and changing versions](/deep-dive-run-and-versions.md) | `run`, `re-run`, `update-version`, `history` | [🕹️ Run an example](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags), [🎯 Is it fixed in a newer version?](/sessions?id=🎯-is-it-fixed-in-a-newer-version) |
| 🗂️ | [Topic administration: create, alter, counts, waiting](/deep-dive-topic-administration.md) | `topic create`, `alter`, `describe`, `list`, `get-number-records`, `get-offsets`, `wait-for-records`, `delete` | [🪛 A producer gets RecordTooLargeException](/sessions?id=🪛-a-producer-gets-recordtoolargeexception) |
| 🔐 | [Secured environments: SASL, SSL, Kerberos, RBAC](/deep-dive-secured-environments.md) | `start-environment --environment …`, `run --environment …`, `rbac role-binding` | [🔐 The same example under SASL_SSL and RBAC](/sessions?id=🔐-the-same-example-under-sasl_ssl-and-rbac) |
| 📈 | [Benchmark a connector](/deep-dive-connector-benchmark.md) | `connector benchmark` | [📈 Is version Y slower?](/sessions?id=📈-is-version-y-slower-benchmark-two-versions) |
| 🌤️ | [Fully managed connectors (Confluent Cloud)](/deep-dive-fully-managed.md) | `connector create-or-update`, `status`, `offsets`… on Confluent Cloud | [🚚 Move to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed), [🏗️ Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform) |
| 🔑 | [Credentials and the 1Password setup](/deep-dive-secrets.md) | `secrets check`, `set`, `import`, `list`, `link`, `backend`, `profile`, `env`, `scan` | [🕹️ Run an example](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) (`secrets set`) |

> [!TIP]
> Each deep dive follows the same outline, so you can jump to the part you need: mental model first, then the commands
> with their gotchas, a hands-on lab, recipes for support repros, and a cheat sheet at the end.
