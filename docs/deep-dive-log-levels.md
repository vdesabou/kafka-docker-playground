# 🍪 Deep dive: log levels (`debug log-level`, `connector log-level`)

The commands that turn up the logs of a running Connect worker **without restarting it and without editing log4j
files**: `TRACE` on the package you suspect, reproduce, read the logs, put it back. `connector log-level` picks the
packages of a connector for you, `debug log-level` takes any package. This is the difference between "the task
failed" and seeing the request that failed, the record that broke it and what the transforms did to it. Takes about
15 minutes to read and run.

> [!TIP]
> The video session [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags)
> shows `--connect-log-level`, which sets the levels before the example creates its connector. This page goes
> further: how the levels are set under the hood, what survives a restart, a hands-on lab and recipes for support
> repros.

| You want | Command |
| --- | --- |
| TRACE on everything that matters for a connector | `playground connector log-level --connector <c> --level TRACE` |
| one package or class, any level | `playground debug log-level set --package <pkg> --level DEBUG` |
| the levels that are set explicitly | `playground debug log-level get` (`--package <pkg>` for one) |
| back to normal | `playground debug log-level set --package <pkg> --level INFO` |
| the levels set before the connector exists | `playground run -f <example> --connect-log-level "<pkg>=TRACE,<pkg2>=DEBUG"` |
| the level right after creating the connector | `playground connector create-or-update -c <c> --level TRACE [--package <pkg>]` |
| levels that survive a restart | `CONNECT_LOG4J_LOGGERS` in the example's docker compose override |

---

## 1. Mental model (the 3 things to remember)

1. **It's the Connect REST API, live, on the worker.** `debug log-level set` is a `PUT /admin/loggers/<package>` on the
   Connect REST API (`localhost:8083`, or the CFK port-forward): the level changes immediately, for that logger
   **and everything below it** in the package hierarchy (`io.confluent.connect.jdbc` covers
   `io.confluent.connect.jdbc.sink.JdbcSinkTask`). On CP 7.7+ the call adds `?scope=cluster`, so every worker of the
   Connect cluster applies it (KIP-976); before, only the worker behind port 8083 changes. Only the
   Connect worker is covered: not the broker, not Schema Registry.

2. **`connector log-level` = the connector's package + 3 runtime classes.** For each connector (all of them without
   `--connector`), it reads `connector.class` and drops the class name: `io.confluent.connect.jdbc.JdbcSinkConnector`
   → `io.confluent.connect.jdbc`. It also sets, at the same level:

   | Logger | Shows |
   | --- | --- |
   | `io.confluent.kafka.schemaregistry.client.rest.RestService` | every Schema Registry REST request (subjects, schema ids) |
   | `org.apache.kafka.connect.runtime.TransformationChain` | each record before and after every SMT |
   | `org.apache.kafka.connect.runtime.WorkerSinkTask` (sink) / `WorkerSourceTask` (source) | polls, puts, commits, offsets |

   Code outside the connector's package is not covered: shared libraries (`io.confluent.connect.storage` for S3 /
   GCS / Azure sinks, `io.debezium` core for Debezium connectors, HTTP clients like `org.apache.http`) need a
   `debug log-level set` of their own.

3. **Nothing is persisted: a worker restart puts the levels back.** The levels live in the memory of the worker's
   log4j. `playground container restart` / `recreate`, a crash, a CFK pod restart: the worker starts again with the
   levels of its configuration (`CONNECT_LOG4J_LOGGERS`, `CONNECT_LOG4J_ROOT_LOGLEVEL`). That's true for every way
   the playground sets levels (`debug log-level`, `connector log-level`, `run --connect-log-level`,
   `create-or-update --level`): they all end up in the same `PUT`. For levels that must survive a
   restart, put them in the compose override of the example.

---

## 2. `debug log-level`: any package, any worker

```bash
# every logger with an explicit level (root and the ones set by the environment or by you)
playground debug log-level get

# one logger
playground debug log-level get --package org.apache.kafka.connect.file

# raise one package, or one class
playground debug log-level set --package io.confluent.connect.jdbc --level TRACE
playground debug log-level set --package org.apache.kafka.clients.consumer.internals.ConsumerCoordinator --level DEBUG

# put it back
playground debug log-level set --package io.confluent.connect.jdbc --level INFO
```

What `get` returns for one logger (raw JSON of the REST API):

```json
{"level":"TRACE","last_modified":1792753743520}
```

A logger nobody has set or used yet doesn't exist for the REST API:

```json
{"error_code":404,"message":"Logger org.apache.kafka.connect.file not found."}
```

It still logs at the level inherited from its parent (`root`, INFO): the 404 only means it has no level of its own.

Gotchas:

- **Four levels only**: `--level` takes `INFO`, `WARN`, `DEBUG` or `TRACE`. To silence a noisy logger, `WARN` is the
  lowest you can set from the CLI (`ERROR` / `OFF` need the REST API by hand).
- **"Put it back" is `--level INFO`, not a reset**: there is no command to remove a level. The logger then stays in
  the `get` list with its explicit level. Note the level from `get --package` before changing it if it wasn't
  `INFO` (the environment sets `org.reflections`, `org.I0Itec.zkclient`… to `ERROR`).
- **`get` without `--package` lists every logger the worker has created**, not only the ones set explicitly: about 550
  on a fresh worker, mostly at `INFO` with `"last_modified": null`. Pipe it to `jq 'with_entries(select(.value.last_modified != null))'`
  to see what was changed.
- **Setting the level it already has is skipped**: `🧬⏭️ Skipping as log level for package <pkg> was already set to
  <level>`. The current level is read first with `GET /admin/loggers/<pkg>`.
- **A package name is not checked**: a typo (`io.confluent.connect.jbdc`) is accepted and creates a logger nobody
  writes to. Copy the package from `connector.class` or from a log line (the logger name is at the end of each line,
  in parentheses). `set --package org.apache.kafka.connect.fiel --level DEBUG` exits 0.
- **TRACE on a broad package floods the log** (`org.apache.kafka` at TRACE is thousands of lines per second): the
  worker slows down, the interesting lines scroll away, and Docker keeps everything. Start with the narrowest
  package, then widen.
- With several workers (`--enable-multiple-connect-workers`), on CP 7.6 and older, only `connect` (port 8083) changes:
  run the same `PUT` on 8283 / 8383 by hand if the task runs elsewhere.
- It's for self-managed Connect: fully managed connectors have no worker you can reach. Use
  `playground connector logs` for what Confluent Cloud exposes.

---

## 3. `connector log-level`: the connector's packages, picked for you

```bash
playground connector log-level --connector jdbc-sink --level TRACE
playground connector log-level --level DEBUG                    # every running connector
playground connector log-level --connector jdbc-sink --level INFO   # back to normal, same 4 loggers
```

What it prints, for a sink:

```text
🔰 also setting io.confluent.kafka.schemaregistry.client.rest.RestService (to see schema registry rest requests) to TRACE
🧬 Set log level for package io.confluent.kafka.schemaregistry.client.rest.RestService to TRACE (scope=cluster)
{"level":"TRACE","last_modified":…}
🔗 also setting org.apache.kafka.connect.runtime.TransformationChain (to see records before and after SMTs) to TRACE
…
🔗 also setting org.apache.kafka.connect.runtime.WorkerSinkTask to TRACE
…
🧬 Set log level for package io.confluent.connect.jdbc to TRACE (scope=cluster)
{"level":"TRACE","last_modified":…}
```

The same thing at deployment time:

```bash
# right after the connector is created or updated
playground connector create-or-update -c jdbc-sink --level TRACE << EOF … EOF
# only one package instead of the 4 loggers
playground connector create-or-update -c jdbc-sink --level DEBUG --package org.apache.kafka.connect.runtime << EOF … EOF

# before the connector is created: the first lines of the task are already at TRACE
playground run -f connect/connect-jdbc-postgresql-sink/postgres-sink.sh --connect-log-level "io.confluent.connect.jdbc=TRACE"
```

Gotchas:

- **`--level` on `create-or-update` comes after the creation**: the task may have started (and failed) before the
  level changes. To catch the first lines, use `run --connect-log-level` (applied as soon as Connect is ready, before
  the example creates anything), or set the level, then create the connector.
- **DEBUG is often not enough**: `WorkerSinkTask` and `TransformationChain` print the records only at `TRACE`. In the
  lab below, `--level DEBUG` adds no line for a new FileStream record; `TRACE` does.
- **The records show up in the log**: `TransformationChain` at TRACE prints each record, `RestService` prints the
  schemas. A log taken with these levels can contain customer data: check it before sharing it.
- `--connector` is optional: without it, **every** connector gets the 4 loggers, sinks and sources alike.
- Fully managed and custom connectors: `connector log-level is not supported with … connector`, exit 0.

---

## 4. Levels that survive a restart: `CONNECT_LOG4J_LOGGERS`

The worker reads its startup levels from environment variables of the `connect` service:

```yaml
# docker-compose.plaintext.yml of the example (or of the repro model)
services:
  connect:
    environment:
      CONNECT_LOG4J_LOGGERS: org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR,org.apache.kafka.connect.runtime.rest.RestServer=ERROR,io.confluent.connect.jdbc=TRACE
      # CONNECT_LOG4J_ROOT_LOGLEVEL: DEBUG
```

| How the level was set | `container restart` | `container recreate` / `re-run` |
| --- | --- | --- |
| `debug log-level`, `connector log-level`, `create-or-update --level` | lost | lost |
| `run --connect-log-level` | lost | lost (`re-run` applies it again) |
| `CONNECT_LOG4J_LOGGERS` in the compose override | kept | kept |

Gotchas:

- **Keep the default entries** of `CONNECT_LOG4J_LOGGERS` when you override it (`org.reflections=ERROR`…): the variable
  replaces the list of the environment, it doesn't add to it.
- `CONNECT_LOG4J_ROOT_LOGLEVEL: DEBUG` (commented out in the environments) changes **everything**: useful once for a
  startup problem, unreadable otherwise.
- The broker and Schema Registry have their own variables (`KAFKA_LOG4J_LOGGERS`, `SCHEMA_REGISTRY_LOG4J_LOGGERS`) and
  are not covered by these commands. A broker logger can also be changed live with
  `kafka-configs --entity-type broker-loggers` (`playground container exec -c broker --command "…"`).

---

## 5. Hands-on lab (≈10 min)

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh
```

The example creates `filestream-sink`, which writes the records of topic `filestream` to `/tmp/output.json` in the
`connect` container.

**Step 1: what is set**

```bash
playground debug log-level get
# 🧬 Get log level for all packages
# { "io.confluent.connect.avro.AvroConverter": {"level": "INFO", "last_modified": null}, …, "org.reflections": {"level": "ERROR", …}, … }
playground debug log-level get --package org.apache.kafka.connect.file
# {"error_code":404,"message":"Logger org.apache.kafka.connect.file not found."}   <- no level of its own yet
```

**Step 2: TRACE on the FileStream package, and its effect**

```bash
playground debug log-level set --package org.apache.kafka.connect.file --level TRACE
# 🧬 Set log level for package org.apache.kafka.connect.file to TRACE (scope=cluster)
# 🧬 Get log level for package org.apache.kafka.connect.file
# {"level":"TRACE","last_modified":1792753743520}
playground topic produce -t filestream --nb-messages 3 --value '{"lab": %g}'
playground container logs -c connect --grep "FileStreamSinkTask" --no-follow --tail 200
# [2026-10-23 11:09:06,035] TRACE [filestream-sink|task-0] Writing line to /tmp/output.json: {lab=1} (org.apache.kafka.connect.file.FileStreamSinkTask:82)
# … {lab=2} … {lab=3}
```

**Step 3: the same level twice is skipped**

```bash
playground debug log-level set --package org.apache.kafka.connect.file --level TRACE
# 🧬⏭️ Skipping as log level for package org.apache.kafka.connect.file was already set to TRACE
```

**Step 4: the connector's loggers in one call**

```bash
playground connector log-level --connector filestream-sink --level DEBUG
# 🔰 also setting io.confluent.kafka.schemaregistry.client.rest.RestService … to DEBUG
# 🔗 also setting org.apache.kafka.connect.runtime.TransformationChain … to DEBUG
# 🔗 also setting org.apache.kafka.connect.runtime.WorkerSinkTask to DEBUG
# 🧬 Set log level for package org.apache.kafka.connect.file to DEBUG (scope=cluster)   <- lowered from TRACE
playground debug log-level get --package org.apache.kafka.connect.runtime.WorkerSinkTask
# {"level":"DEBUG", …}
```

**Step 5: back to normal**

```bash
playground connector log-level --connector filestream-sink --level INFO
playground debug log-level get
# the 4 loggers are still listed, now with "level": "INFO" and a "last_modified" 
```

**Step 6: a restart forgets everything**

```bash
playground debug log-level set --package org.apache.kafka.connect.file --level TRACE
playground container restart -c connect
playground connector wait --connector filestream-sink --max-wait 180
playground debug log-level get --package org.apache.kafka.connect.file
# 🔁 Restarting docker container connect … 🚦 containers have started! (took 6 seconds)
# ✅ 🌎onprem connector filestream-sink is RUNNING (1 task(s)) after 11 seconds
# {"error_code":404,"message":"Logger org.apache.kafka.connect.file not found."}   <- the TRACE is gone
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "the task fails, the stack trace isn't enough" | `connector log-level --connector <c> --level TRACE`, `connector restart`, then `container logs -c connect --errors --since 5m` and `--grep "<connector>" --no-follow` |
| "an SMT changes / drops the record" | `debug log-level set --package org.apache.kafka.connect.runtime.TransformationChain --level TRACE` (or `connector smt test`) |
| "schema not found / wrong schema id" | `debug log-level set --package io.confluent.kafka.schemaregistry.client.rest.RestService --level DEBUG`: each SR request with its subject and id |
| "the sink doesn't commit / rebalances" | `WorkerSinkTask` and `org.apache.kafka.clients.consumer.internals.ConsumerCoordinator` at `DEBUG` |
| "HTTP sink / Salesforce / any REST connector: what is sent?" | the connector package **and** the HTTP client (for an Apache HttpClient based connector: `org.apache.http` at `DEBUG`, the wire log `org.apache.http.wire` at `DEBUG`) |
| "S3 / GCS sink: when are files rolled?" | `io.confluent.connect.s3` **and** `io.confluent.connect.storage` at `DEBUG` |
| "the problem happens at startup" | `playground run … --connect-log-level "<pkg>=TRACE"`: set before the connector is created |
| "the logs must be at TRACE after a restart" (worker crash, rolling restart) | `CONNECT_LOG4J_LOGGERS` in the compose override of the repro model |
| "the customer can't restart the worker" | same `PUT /admin/loggers/<pkg>` on their worker: what `debug log-level set` does, so the command line is the answer |

In a repro model, raise the levels right before the step that fails, and lower them after, so the log stays readable:

```bash
playground connector log-level --connector my-sink --level TRACE
playground topic produce -t my-topic --nb-messages 1 --forced-value '{"id": 1}'
playground connector wait --connector my-sink --state FAILED --max-wait 120
playground container logs -c connect --errors --since 5m
playground connector log-level --connector my-sink --level INFO
```

---

## 7. Cheat sheet

```bash
playground debug log-level get [--package <pkg>]
playground debug log-level set --package <pkg> --level INFO|WARN|DEBUG|TRACE
playground connector log-level [--connector <c>] --level INFO|WARN|DEBUG|TRACE
playground connector create-or-update -c <c> --level TRACE [--package <pkg>] << EOF … EOF
playground run -f <example> --connect-log-level "<pkg>=TRACE,<pkg2>=DEBUG"
```

- `PUT /admin/loggers/<pkg>` on the Connect REST API: immediate, no restart, the package and everything below it.
- CP 7.7+: `scope=cluster`, all workers. Older: the worker on 8083 only.
- `connector log-level` = package of `connector.class` + `RestService` + `TransformationChain` + `WorkerSinkTask` /
  `WorkerSourceTask`.
- Lost on restart. Persistent: `CONNECT_LOG4J_LOGGERS` in the compose override.
- Back to normal = `--level INFO`. TRACE logs can hold records: check before sharing.
- Sources: [`debug/log-level/set.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/log-level/set.sh),
  [`debug/log-level/get.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/debug/log-level/get.sh),
  [`connector/log-level.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/log-level.sh),
  `apply_connect_log_levels` / `get_connect_url_and_security` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) (`--connect-log-level`)
- 🍪 Deep dives: [`container logs` and `analyze logs`](/deep-dive-container-logs.md) to read what the new levels print,
  [`connector diagnose` and the dead letter queue](/deep-dive-connector-troubleshooting.md) for what to look at first
- 📖 [Connectors logging](/reusables?id=🔗-connectors) in the Reproduction toolkit, and the Confluent docs on
  [changing the log level of a logger](https://docs.confluent.io/platform/current/connect/logging.html#change-the-log-level-for-a-specific-logger)
- 🧠 CLI reference: [playground debug log-level](/playground%20debug%20log-level),
  [playground connector log-level](/playground%20connector%20log-level), [playground run](/playground%20run)
