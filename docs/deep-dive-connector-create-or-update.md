# 🍪 Deep dive: `playground connector create-or-update`

The command every example uses to deploy its connector: the JSON config comes from a heredoc, the connector is
created or updated in place, and the command **waits for the connector and its tasks to be RUNNING**, so a broken
config stops the script right there instead of failing silently later. Its companions check a config before you
deploy it (`validate`), compare it with a customer's (`diff`), wait for any state (`wait`), and show what runs
(`status`, `show-config`, `update`). Takes about 15 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session [🔌 The sink fails right after it is deployed](/sessions?id=🔌-the-sink-fails-right-after-it-is-deployed) shows it in 3 minutes: a config that validates but fails on its first record, the wait that stops on the FAILED task, `--dry-run` and the update in place.
>
> The video session [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
> picks up where this page stops: the connector is deployed, now why doesn't it work? This page covers getting it
> deployed: how the command works under the hood, its gotchas, a hands-on lab and recipes for support repros.

| You want | Command |
| --- | --- |
| create or update a connector, and fail if it doesn't run | `playground connector create-or-update -c <name> << EOF … EOF` |
| the same, from a customer's file (REST API format accepted) | `playground connector create-or-update -c <name> customer.json` |
| the same, from a CFK / Strimzi custom resource, terraform, a `.properties` file, a `?expand=info` dump | `playground connector create-or-update -c <name> customer.yaml` (detected, adapted to the playground) |
| convert a config to another format (heredoc for a repro, CFK CR or terraform to answer the customer) | `playground connector convert customer.yaml [--to heredoc\|json\|cfk\|strimzi\|terraform\|properties]` |
| check a config without deploying it | `playground connector validate << EOF … EOF`, or `create-or-update --validate` |
| see what would be sent | `create-or-update --dry-run` |
| a connector that is expected to fail | `create-or-update --no-wait`, then `playground connector wait -c <name> --state FAILED` |
| create it stopped or paused | `create-or-update --initial-state STOPPED\|PAUSED` (CP 7.7+) |
| compare with a customer's config, another connector, or the defaults | `playground connector diff -c <name> --file cfg.json \| --with-connector <other> \| --defaults` |
| the state and the stack trace | `playground connector status [-c <name>]` |
| the running config, ready to paste back | `playground connector show-config -c <name>` |
| edit it in your editor | `playground connector update -c <name>` |

---

## 1. Mental model (the 3 things to remember)

1. **Create and update are the same call.** The command lists the connectors: if `<name>` exists, it's updated with
   `PUT /connectors/<name>/config`, otherwise created the same way. So you can re-run the command (or the whole
   script) while you iterate on a config. An update prints what changed compared to the running config, secrets
   masked:

   ```text
   🔍 changes compared to the running config:
      + errors.tolerance: all
      ~ tasks.max: 1 → 2
      - file
   ```

   A `PAUSED` or `STOPPED` connector **stays** paused or stopped after an update. The config can be a plain JSON object
   or the REST API format (`{"name": …, "config": {…}}`, what `GET /connectors/<name>` returns): the outer `name` is
   ignored, and a `name` key inside the config that differs from `--connector` is replaced, with a warning.

   It also reads the other formats customers send, detected from the content: a dump of
   `GET /connectors?expand=info` (the entry named `--connector`), a CFK `Connector` or Strimzi `KafkaConnector` custom
   resource (`spec.class`, `spec.taskMax` / `spec.tasksMax`, `spec.configs` / `spec.config`, several documents
   allowed), a terraform `confluent_connector` resource (`config_nonsensitive` + `config_sensitive`), a
   `connect-standalone` `.properties` file. A config that comes from elsewhere (a file, or one of these formats) is
   **adapted to the playground**: bootstrap servers and schema registry urls whose hosts are not containers of the
   playground, the credentials of that schema registry, a license, replication factors above the number of brokers, and
   on plaintext the security of the clients whose bootstrap servers were rewritten (`--no-adapt` to keep it as is,
   `--adapt` for a plain json heredoc too). Masked secrets (`****`, `[hidden]`), config providers of the customer
   environment (`${file:/mnt/...}`), terraform references (`var.x`) and the keys still pointing to external systems are
   listed. The heredocs of the examples are never changed. `playground connector convert` writes any of these formats
   in another one (`--secrets-as-variables` also turns the plaintext passwords, keys and tokens into variables, for a
   heredoc that goes in a committed script; `playground repro bootstrap --config` builds a whole reproduction model
   from the file). Step 8 of the [hands-on lab](/deep-dive-connector-create-or-update?id=_5-hands-on-lab-≈10-min) shows each format with its output.

2. **It waits, and how strict it is depends on what runs.** After the update, a self-managed connector is polled
   (`playground connector wait`, every 5 s, up to `--max-wait`, default 120 s) until the connector **and all its
   tasks** are RUNNING:
   - a FAILED connector or task stops the wait right away, with the stack trace (a failed task doesn't recover on its
     own).
   - RUNNING only counts when it's still RUNNING one check later: a task is RUNNING before its first record and can
     fail right after.
   - a connector RUNNING with no task for 30 s (nothing to process yet: JDBC source without table, Replicator without
     topic) is accepted with a warning.

   What happens when it's not RUNNING depends on the script that `playground run` last ran (`run.test_file` in
   `playground.ini`):

   | | example | reproduction model (path contains `/reproduction-models/`) |
   | --- | --- | --- |
   | default | ❌ exit 1 | ⚠️ warning, the script goes on (repro models often create a failing connector on purpose) |
   | `--wait` | ❌ exit 1 | ❌ exit 1 |
   | `--no-wait` | status shown, no wait | status shown, no wait |

   Fully managed connectors are only waited for with `--wait` (up to 600 s by default, restarted if they fail while
   being provisioned).

3. **It adapts the config to the environment, and remembers it.** Before sending, the config gets the
   environment's settings (`add_connector_config_based_on_environment`): on SASL / SSL / Kerberos / RBAC /
   Confluent Cloud environments, keys like `confluent.topic.bootstrap.servers`, `*.converter.schema.registry.url`,
   `schema.history.internal.kafka.*` or `reporter.bootstrap.servers` get the right bootstrap server and security
   properties. On CFK, it becomes a `Connector` custom resource applied with `kubectl`. Use
   `--skip-automatic-connector-config` to send the config exactly as written, and `--dry-run` to see the final config.
   The config sent is saved in `/tmp/config-<name>` (readable by you only, it can hold passwords): `show-config` reads
   it back, and on macOS it's copied to the clipboard as a ready-to-paste heredoc.

---

## 2. Deploying: config in, connector out

```bash
# the usual form: a heredoc (unquoted EOF, so that $VARIABLES are replaced)
playground connector create-or-update -c filestream-sink << EOF
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false"
}
EOF

# a file (path or @path): a customer's config, plain or REST API format, or a CFK / Strimzi custom resource, terraform,
# a .properties file, a dump of GET /connectors?expand=info (adapted to the playground, --no-adapt to keep it as is)
playground connector create-or-update -c filestream-sink customer-connector.json

# check it first: every invalid property at once, nothing deployed if one is invalid
playground connector create-or-update -c filestream-sink --validate customer-connector.json

# the final config (with the environment settings) and the request, nothing deployed
playground connector create-or-update -c filestream-sink --dry-run customer-connector.json

# log level of the connector (or of one package) right after the creation
playground connector create-or-update -c filestream-sink --level TRACE customer-connector.json
playground connector create-or-update -c filestream-sink --level DEBUG --package org.apache.kafka.connect.runtime customer-connector.json
```

Gotchas:

- **Quoted or unquoted `EOF`.** `<< EOF` replaces `$VAR` and `$(…)` in the config (what examples want for
  credentials). A regex with `$` or `\d` needs `<< 'EOF'`, or `\$` / `\\d`. The clipboard copy always uses
  `<< 'EOF'` so that it pastes back byte for byte.
- **Invalid JSON is caught before anything is sent**, with the jq error and the line highlighted. In a terminal, the
  file opens in your editor to fix it; in a script, CI or an agent, the command exits 1.
- **No stdin, no wait**: with nothing on stdin (a terminal, or nothing within 3 s), the command fails with
  `no connector config on stdin` rather than hanging.
- `--validate` uses the plugin's own validation (`PUT /connector-plugins/<class>/config/validate`): it catches types,
  missing required keys, invalid values. It doesn't catch a wrong hostname or a missing table: those fail when the
  task starts, which is what the wait is for.
- `--level` / `--package` and `--initial-state` are self-managed only. `--offsets` is fully managed only, and only at
  creation.
- On CFK, the connector name is a Kubernetes resource name: lower case, digits, `-` and `.` only.

---

## 3. Waiting: `--wait`, `--no-wait`, `connector wait`

```bash
# default: wait up to 120 s for RUNNING (strict in examples, warning in repro models)
playground connector create-or-update -c my-sink << EOF … EOF

# slow to start (big snapshot, slow external system): wait longer
playground connector create-or-update -c my-source --max-wait 300 << EOF … EOF

# a connector that must fail: don't wait for RUNNING, wait for FAILED
playground connector create-or-update -c my-sink --no-wait << EOF … EOF
playground connector wait -c my-sink --state FAILED --max-wait 120

# any state, after a pause / stop / an external event
playground connector pause -c my-sink
playground connector wait -c my-sink --state PAUSED --max-wait 60

# create it stopped, then start it when the data is ready (CP 7.7+)
playground connector create-or-update -c my-sink --initial-state STOPPED << EOF … EOF
playground connector resume -c my-sink
```

What the wait prints:

```text
⏳ Waiting up to 120 seconds for 🌎onprem connector filestream-sink to be RUNNING
✅ 🌎onprem connector filestream-sink is RUNNING (1 task(s)) after 6 seconds
```

Gotchas:

- **`--state FAILED` is reached when any task is FAILED**, even if the connector itself is still RUNNING (the usual
  case when only a task fails).
- **A Datagen task that completed its `iterations` counts as RUNNING.** Datagen stops each task on purpose once it has
  produced its messages (`ConnectException: Stopping connector: generated the configured N number of messages`), so
  Connect shows it FAILED: the wait treats that trace as completed, any other FAILED task still fails it.
  `connector status` keeps showing FAILED, the real state in Connect.
- `--wait-for-zero-lag` additionally waits for the consumer lag of a sink to reach 0 (`connector show-lag`): the
  replacement for `sleep` before checking the data landed. A source connector is skipped with a warning.
- The strict / warning choice comes from the **last `playground run`**, not from the script that calls the command.
  After `playground start-environment` by hand, the mode is the one of the last script you ran (strict when there is
  none).
- `--no-wait` conflicts with `--wait` and `--max-wait`. `--dry-run` never waits.
- **A paused connector keeps its old tasks.** After an update of `tasks.max` while PAUSED, the wait reports the old
  task count; the new tasks are created on `resume`. Right after `resume`, `status` can show the connector still
  `PAUSED` with its tasks already `RUNNING` for a second or two.

---

## 4. Inspecting and comparing: `status`, `show-config`, `diff`, `update`

```bash
# state of the connector and of each task, with the stack trace of what failed
playground connector status -c filestream-sink

# the config, as a create-or-update heredoc you can paste in a repro model
playground connector show-config -c filestream-sink
playground connector show-config -c filestream-sink --force-rest-endpoint   # what the worker returns (GET /config)

# what differs from the customer's config
playground connector diff -c filestream-sink --file customer-connector.json

# what differs from another connector, or which keys are not at their default
playground connector diff -c filestream-sink --with-connector filestream-sink-2
playground connector diff -c filestream-sink --defaults

# edit the running config in your editor: saved = applied
playground connector update -c filestream-sink
```

`diff` output:

```text
🔀 Diff of connector filestream-sink (➖) with customer-connector.json (➕)
  ✏️  tasks.max
       ➖ 1
       ➕ 4
  ➖ key.converter = org.apache.kafka.connect.storage.StringConverter   (only in filestream-sink)
  ➖ value.converter = org.apache.kafka.connect.json.JsonConverter   (only in filestream-sink)
  ➖ value.converter.schemas.enable = false   (only in filestream-sink)
📊 4 key(s) differ, 4 identical
```

Gotchas:

- **`show-config` shows what you sent, not what runs.** It reads `/tmp/config-<name>` when it exists, so it shows the
  config as written by your last `create-or-update` from this machine (passwords in clear). `--force-rest-endpoint`
  asks the worker instead: passwords are masked there, and the keys the worker adds show up.
- `diff --file` accepts a plain config, the REST API format, a heredoc as printed by `show-config`, and the other
  formats of `create-or-update` (CFK / Strimzi custom resource, terraform, `.properties`, `?expand=info` dump: the entry
  named like the connector). It compares the file as it is, without adapting it. Passwords masked
  by the REST API (`****`, `[hidden]`) are listed as not compared, never as different.
- `diff --defaults` lists the keys set to a non-default value, the keys set to their default (they could be removed),
  and the keys that are not plugin parameters (converters, transforms, worker overrides). Not on CFK.
- `diff` also writes a self-contained **HTML report**, `diff-<connector>-<other>-<date>.html` in `--output-dir`
  (default `/tmp/playground-connector-diff`), opened in the browser from a terminal (`--no-open` to skip; never with
  `--json`). The report has:
  - the keys side by side, with the documentation, type and default of each one, from the configuration reference of
    the plugin (`.connector_config/config-<class>-<version>.txt`, else the one recorded by CI)
  - what the important differences mean: converters, error handling, transforms, topics, client overrides, security
  - the secrets masked (the REST API of a self-managed worker returns them in clear)
- `status` on a FAILED connector ends with a hint: `playground connector diagnose --connector <name>` gives the error
  digest, the lag and the next steps.
- When the wait for RUNNING finds a FAILED connector or task, `create-or-update` / `wait` run that
  `connector diagnose` for you (connect errors since the wait started, 5 findings at most), so the output of a
  failed example or CI job already has the digest and the path of the HTML report. From an interactive terminal the
  report opens in the browser (never in CI): `playground config open-diagnose-report-on-failure false` to only print
  its path. Set `PG_SKIP_AUTO_DIAGNOSE=1` to get only the status.
- `update` opens the config **and** the list of every parameter of the plugin in your editor: it's interactive, not for
  scripts.

---

## 5. Hands-on lab (≈10 min)

```bash
playground run -f connect/connect-filestream-sink/filestream-sink.sh
```

The example creates `filestream-sink` with `--wait` and leaves it RUNNING.

**Step 1: what runs**

```bash
playground connector status -c filestream-sink
# filestream-sink                ✅ RUNNING  0:🟢 RUNNING                 -
playground connector show-config -c filestream-sink
# 🧰 Current config for 🌎onprem connector filestream-sink
# playground connector create-or-update --connector filestream-sink << 'EOF'
# { "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector", "file": "/tmp/output.json", … }
# EOF
```

**Step 2: update in place, and see the changes**

```bash
playground connector create-or-update -c filestream-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output2.json",
  "key.converter": "org.apache.kafka.connect.storage.StringConverter",
  "value.converter": "org.apache.kafka.connect.json.JsonConverter",
  "value.converter.schemas.enable": "false",
  "errors.tolerance": "all"
}
EOF
# 🔄 Updating 🌎onprem connector filestream-sink
# 🔍 changes compared to the running config:
#    + errors.tolerance: all
#    ~ file: /tmp/output.json → /tmp/output2.json
# ⏳ Waiting up to 120 seconds for 🌎onprem connector filestream-sink to be RUNNING
# ✅ 🌎onprem connector filestream-sink is RUNNING (1 task(s)) after 6 seconds
```

**Step 3: validate before deploying**

```bash
playground connector validate << 'EOF'
{
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/tmp/output.json",
  "tasks.max": "abc"
}
EOF
# ❌ Validation errors found in connector config
# tasks.max ->> Invalid value abc for configuration tasks.max: Not a number of type INT, …
echo $?   # 1
```

**Step 4: a connector that fails, strict vs `--no-wait`**

```bash
# the task can't open its file: the connector is created (validation doesn't check paths), the task fails when it starts
playground connector create-or-update -c broken-sink << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/does/not/exist/output.json"
}
EOF
# ✅ 🌎onprem connector broken-sink was successfully created
# ⏳ Waiting up to 120 seconds for 🌎onprem connector broken-sink to be RUNNING
# ❌ 🌎onprem connector broken-sink is FAILED, not waiting for it to be RUNNING
# 🩺 diagnosing 🌎onprem connector broken-sink              <- connector diagnose runs on its own
# 🗺️  1/4 status
# broken-sink   ✅ RUNNING  0:🛑 FAILED   tasks: org.apache.kafka.connect.errors.ConnectException: Couldn't find or create file '/does/not/exist/output.json' for FileStreamSinkTask
#   … Caused by: java.nio.file.NoSuchFileException: /does/not/exist/output.json
# 🔥 2/4 errors: digest of connect ERROR/FATAL records since 120s (whole worker, not only this connector)
# …
# 👉 4/4 next steps
#    🔥 a task or the connector FAILED: read the trace above, then after a fix: playground connector restart --connector broken-sink
# …
# ❌ 🌎onprem connector broken-sink is not RUNNING (use --no-wait to skip the wait)
echo $?   # 1

playground connector delete -c broken-sink
playground connector create-or-update -c broken-sink --no-wait << 'EOF'
{
  "tasks.max": "1",
  "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
  "topics": "filestream",
  "file": "/does/not/exist/output.json"
}
EOF
playground connector wait -c broken-sink --state FAILED --max-wait 60
# ✅ 🌎onprem connector broken-sink is FAILED after 0 seconds        <- the connector is RUNNING, its task is FAILED
playground connector delete -c broken-sink
```

**Step 5: compare with a customer's config**

```bash
cat > /tmp/customer-connector.json << 'EOF'
{
  "name": "customer-sink",
  "config": {
    "tasks.max": "4",
    "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
    "topics": "filestream",
    "file": "/tmp/output2.json",
    "errors.tolerance": "all"
  }
}
EOF
playground connector diff -c filestream-sink --file /tmp/customer-connector.json
# ✏️  tasks.max  ➖ 1  ➕ 4
# ➖ key.converter = org.apache.kafka.connect.storage.StringConverter   (only in filestream-sink)
# 📊 4 key(s) differ, 4 identical
# ✅ HTML report saved: /tmp/playground-connector-diff/diff-filestream-sink-customer-connector.json-<date>.html   <- 🔀 another converter
playground connector diff -c filestream-sink --defaults
#   ✏️  errors.tolerance = all   (default: none)
#   ✏️  value.converter = org.apache.kafka.connect.json.JsonConverter   (default: io.confluent.connect.avro.AvroConverter)
# 📊 4 parameter(s) differ from their default, 2 are set to their default value (they could be removed)
#   💤 tasks.max = 1
#   💤 key.converter = org.apache.kafka.connect.storage.StringConverter
```

**Step 6: the REST API format, and `--dry-run`**

```bash
playground connector create-or-update -c filestream-sink --dry-run /tmp/customer-connector.json
# 📄 reading the connector config from /tmp/customer-connector.json
# 📦 detected: REST API format ({"name": ..., "config": {...}})
# 🔍 changes compared to the running config:
#    - key.converter
#    - value.converter
#    - value.converter.schemas.enable
#    ~ tasks.max: 1 → 4
# 🌵 --dry-run: 🌎onprem connector filestream-sink would be updated with this config
# 🌵 request: PUT http://localhost:8083/connectors/filestream-sink/config
```

**Step 7: a paused connector stays paused**

```bash
playground connector pause -c filestream-sink
playground connector create-or-update -c filestream-sink /tmp/customer-connector.json
# ⏸️ 🌎onprem connector filestream-sink is PAUSED, it stays PAUSED after the update
# ✅ 🌎onprem connector filestream-sink is PAUSED (1 task(s)) after 0 seconds      <- still 1 task while paused
playground connector resume -c filestream-sink
playground connector status -c filestream-sink
# filestream-sink   ✅ RUNNING  0:🟢 RUNNING,1:🟢 RUNNING,2:🟢 RUNNING,3:🟢 RUNNING   <- the 4 tasks start on resume
```

**Step 8: the formats customers send (CFK, terraform, `.properties`, REST dumps)**

A customer rarely sends REST JSON. They send what they deploy with. The files below are the fixtures of
[`tools/connector-config/fixtures`](https://github.com/vdesabou/kafka-docker-playground/tree/master/tools/connector-config/fixtures)
(made up, shaped like real customer files); run the commands from the root of the repository.

*8a. A CFK `Connector` resource, deployed as is.* `cfk-filestream-sink.yaml` has `spec.class`, `taskMax: 1`, and in
`spec.configs` the customer's Schema Registry with its credentials, their license, and a dead letter queue with
`replication.factor: 3`, as on their 3-broker cluster:

```bash
playground connector create-or-update -c filestream-cfk tools/connector-config/fixtures/cfk-filestream-sink.yaml
# 📄 reading the connector config from tools/connector-config/fixtures/cfk-filestream-sink.yaml
# 📦 detected: CFK Connector custom resource (spec.class, spec.taskMax, spec.configs)
# 🔧 adapted to the playground (--no-adapt to keep the config as is):
#    - confluent.license
#    - value.converter.basic.auth.credentials.source
#    - value.converter.basic.auth.user.info
#    errors.deadletterqueue.topic.replication.factor: 3 → 1
#    value.converter.schema.registry.url: https://sr.prod.example.com:8081 → http://schema-registry:8081
# 🛠️ Creating 🌎onprem connector filestream-cfk
# ✅ 🌎onprem connector filestream-cfk is RUNNING (1 task(s)) after 11 seconds
```

`spec.class` became `connector.class`, `taskMax: 1` became `"tasks.max": "1"`, `3` became a string. The edits that
otherwise fail the first run are done and printed: a DLQ topic with a replication factor of 3 cannot be created on one
broker, and the customer's Schema Registry is not reachable. Only values that point outside the playground are rewritten:
a host that is a playground container (`broker`, `broker-us`, `schema-registry`…), `localhost` or `*.confluent.cloud`
is kept.

*8b. What differs from the customer, now.* `diff --file` reads the same resource, as it is:

```bash
playground connector diff -c filestream-cfk --file tools/connector-config/fixtures/cfk-filestream-sink.yaml
# 📦 tools/connector-config/fixtures/cfk-filestream-sink.yaml: CFK Connector custom resource (spec.class, spec.taskMax, spec.configs)
# 🔀 Diff of connector filestream-cfk (➖) with cfk-filestream-sink.yaml (➕)
#   ✏️  errors.deadletterqueue.topic.replication.factor
#        ➖ 1
#        ➕ 3
#   ✏️  value.converter.schema.registry.url
#        ➖ http://schema-registry:8081
#        ➕ https://sr.prod.example.com:8081
#   ➕ confluent.license = eyJhbGciOiJSUzI1NiJ9.customer-license   (only in cfk-filestream-sink.yaml)
#   ➕ value.converter.basic.auth.credentials.source = USER_INFO   (only in cfk-filestream-sink.yaml)
#   ➕ value.converter.basic.auth.user.info = sr-user:sr-password   (only in cfk-filestream-sink.yaml)
# 📊 5 key(s) differ, 9 identical
```

The only differences are the adaptations: everything else runs with the customer's values. (The terminal prints the
values of the file in clear; the HTML report masks the secrets.)

*8c. A CFK file with two connectors and a mounted secret, turned into a repro heredoc.* `cfk-connectors.yaml` holds two
`Connector` documents; the JDBC one reads its password from a CFK mounted secret, talks to a SASL_SSL cluster for its
license topic, and uses a production Schema Registry:

```bash
playground connector convert tools/connector-config/fixtures/cfk-connectors.yaml
# ❌ 2 connectors in the config (jdbc-sink s3-sink), pick one with --connector
playground connector convert tools/connector-config/fixtures/cfk-connectors.yaml --connector jdbc-sink
```

On stderr, what to know:

```text
📦 detected: CFK Connector custom resource (spec.class, spec.taskMax, spec.configs)
🔧 adapted to the playground (--no-adapt to keep the config as is):
   - confluent.topic.security.protocol
   - value.converter.basic.auth.credentials.source
   - value.converter.basic.auth.user.info
   confluent.topic.bootstrap.servers: kafka.prod.example.com:9092 → broker:9092
   confluent.topic.replication.factor: 3 → 1
   errors.deadletterqueue.topic.replication.factor: 3 → 1
   value.converter.schema.registry.url: https://schemaregistry.prod.example.com:8081 → http://schema-registry:8081
🌍 still pointing to the customer environment (external systems, files): use the ones of the example
   connection.url=jdbc:postgresql://db.prod.example.com:5432/orders
⚠️ 1 value(s) to fill in, they cannot work as they are:
   connection.password: config provider of the customer environment (${file:/mnt/secrets/jdbc-credentials/creds.properties:password})
```

On stdout, ready to paste in a reproduction model (`convert ... > repro-config.sh` keeps only this part):

```bash
# values to fill in before running it:
#   export CONNECTION_PASSWORD=...   # connection.password: config provider of the customer environment (${file:/mnt/secrets/jdbc-credentials/creds.properties:password})
playground connector create-or-update --connector jdbc-sink << EOF
{
  "name": "jdbc-sink",
  "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
  "tasks.max": "4",
  "topics": "orders",
  "connection.url": "jdbc:postgresql://db.prod.example.com:5432/orders",
  "connection.user": "app",
  "connection.password": "${CONNECTION_PASSWORD}",
  "auto.create": "true",
  "transforms": "route",
  "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
  "transforms.route.regex": "(.*)",
  "transforms.route.replacement": "prod_\$1",
  "value.converter": "io.confluent.connect.avro.AvroConverter",
  "value.converter.schema.registry.url": "http://schema-registry:8081",
  "confluent.topic.bootstrap.servers": "broker:9092",
  "confluent.topic.replication.factor": "1",
  "errors.deadletterqueue.topic.replication.factor": "1"
}
EOF
```

The secret the CFK pod reads from a mounted file becomes a variable instead of a value that silently fails. The heredoc
is unquoted for that variable, so `$1` is escaped as `\$1` (bash gives back `prod_$1`). The JDBC URL is listed as the
one thing to replace with the database of the example.

*8d. Terraform, a fully managed connector.* `terraform-confluent-connector.tf` is a `confluent_connector` resource with
references to other resources and variables:

```bash
playground connector convert tools/connector-config/fixtures/terraform-confluent-connector.tf
# 📦 detected: terraform confluent_connector resource "sink" (config_nonsensitive + config_sensitive)
# ☁️ connector.class S3_SINK is a fully managed connector: run it as a fully managed example (ccloud/fm-*), the self-managed plugin has another class and other keys
# ⚠️ 4 value(s) to fill in, they cannot work as they are:
#    topics: terraform reference (confluent_kafka_topic.orders.topic_name)
#    kafka.service.account.id: terraform reference (confluent_service_account.app-connector.id)
#    s3.bucket.name: terraform reference (${var.prefix}-bucket)
#    aws.secret.access.key: terraform reference (var.aws_secret)
```

followed by the heredoc with `"topics": "${TOPICS}"`, `"aws.secret.access.key": "${AWS_SECRET_ACCESS_KEY}"`… and
`"flush.size": "1000"` (a number in HCL, a string for Connect). `config_sensitive` is merged, and no Terraform expression
is sent as a literal value.

*8e. Answer a CFK customer in their format.* The repro used a `connect-standalone` file; the customer runs CFK:

```bash
playground connector convert tools/connector-config/fixtures/connect-standalone.properties --to cfk
# 📦 detected: connect-standalone .properties file
apiVersion: platform.confluent.io/v1beta1
kind: Connector
metadata:
  name: s3-sink
  namespace: confluent
spec:
  class: io.confluent.connect.s3.S3SinkConnector
  taskMax: 2
  connectClusterRef:
    name: connect
  configs:
    topics.regex: orders-.*
    transforms: route
    transforms.route.type: org.apache.kafka.connect.transforms.RegexRouter
    transforms.route.regex: (.*)\.public\.(.*)
    transforms.route.replacement: $1_$2
    s3.bucket.name: my-bucket
    key.converter.basic.auth.user.info: user:pass
```

The `.properties` file has what breaks a hand (or `yq -p props`) conversion: `transforms=route` next to
`transforms.route.*`, a `\\.` escape in a regex, a `my-\` line continuation, `\:` in a value, `:` and space
separators, a `!` comment. `--to terraform`, `--to strimzi`, `--to properties`, `--to json` work the same way, and
every output converts back to the same config.

*8f. A `.properties` file to validate, a dump of several connectors to deploy:*

```bash
playground connector validate < tools/connector-config/fixtures/filestream-sink.properties
# 📦 detected: connect-standalone .properties file
# ❌ Validation errors found in connector config
# tasks.max ->> Invalid value abc for configuration tasks.max: Not a number of type INT, Invalid value null for configuration tasks.max: Value must be non-null
playground connector create-or-update -c filestream-source --dry-run tools/connector-config/fixtures/rest-expand-info.json
# 📦 detected: dump of GET /connectors?expand=info
# 🌵 --dry-run: 🌎onprem connector filestream-source would be created with this config
```

The heredocs of the examples (plain JSON on stdin) are never adapted: no detection line, no change. `--adapt` adapts a
customer config pasted in a heredoc.

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "here is our connector config" (JSON from the UI / REST API) | `create-or-update -c <name> customer.json --validate`: REST API format accepted, every invalid key at once |
| "here is our CFK Connector resource" (or Strimzi, terraform, `connect-standalone` `.properties`) | `create-or-update -c <name> connector.yaml --validate`: detected and adapted to the playground; `connector convert connector.yaml` prints the heredoc for the repro model, with the values to fill in as variables |
| "here is the output of `curl /connectors?expand=info`" | `create-or-update -c <one of them> dump.json`, or `connector convert dump.json -c <name>` |
| "answer the customer in their format" | `connector convert repro.json --to cfk` (or `--to terraform`, `--to strimzi`, `--to properties`) |
| "it works for us with this config, not for you" | `diff -c <name> --file customer.json`, then `diff --defaults` to drop the noise |
| "the connector fails right after it starts" | default wait: the stack trace of the failed task, the script stops there |
| "reproduce a connector that must fail" | `--no-wait`, then `connector wait --state FAILED --max-wait 120` (no `sleep`) |
| "we create it stopped, set offsets, then start it" | `--initial-state STOPPED`, `playground connector offsets alter`, `connector resume` (CP 7.7+) |
| "the config works on plaintext, not on SASL / SSL" | run the example with `--environment sasl-ssl`, compare with `--dry-run` and `--skip-automatic-connector-config` |
| "a config change didn't take effect" | `show-config --force-rest-endpoint` (what the worker has) vs `show-config` (what was sent) |
| "TRACE logs of the connector from the start" | `--level TRACE` (or `--level TRACE --package <pkg>`) on create-or-update |
| "check the data landed without a `sleep`" | sink: `--wait-for-zero-lag`; source: `playground topic consume --min-expected-messages N` |

In a repro model, the default is a warning: the script goes on so that you can look at the failure. When the repro
must stop if the connector doesn't start, use `--wait`.

---

## 7. Cheat sheet

```bash
playground connector create-or-update -c <name> [<file>|@<file>] [<< EOF … EOF] \
  [--validate] [--dry-run] [--wait|--no-wait] [--max-wait S] [--wait-for-zero-lag] \
  [--initial-state RUNNING|PAUSED|STOPPED] [--level TRACE [--package <pkg>]] \
  [--skip-automatic-connector-config] [--offsets '<json>' (fully managed)] [--terraform (fully managed)] [--verbose]
playground connector validate [-c <name>] [<< EOF … EOF]
playground connector convert [<file>] [-c <name>] [--to heredoc|json|cfk|strimzi|terraform|properties] [--from <format>] [--no-adapt] [--json]
playground connector wait -c <name> [--state RUNNING|PAUSED|STOPPED|FAILED] [--max-wait 120] [--interval 5]
playground connector diff -c <name> --file <cfg> | --with-connector <other> | --defaults [--json] [--output-dir <dir>] [--no-open]
playground connector status | show-config [--force-rest-endpoint] | update   [-c <name>]
```

- Create = update: re-run freely. An update prints the changed keys, and keeps PAUSED / STOPPED.
- A file or another format (CFK / Strimzi CR, terraform, `.properties`, `?expand=info` dump) is detected and adapted
  to the playground (`--no-adapt`); the heredocs of the examples are never changed. `convert` writes any format.
- Waits for the connector **and its tasks** RUNNING: strict in examples, warning in repro models, `--wait` strict
  everywhere, `--no-wait` none. Fully managed: only with `--wait`.
- The environment's settings are added for you: `--dry-run` shows them, `--skip-automatic-connector-config` removes
  them.
- `show-config` = what you sent (`/tmp/config-<name>`). `--force-rest-endpoint` = what runs.
- `diff` writes a side-by-side HTML report with the doc and default of each key, and the secrets masked.
- Sources: [`connector/create-or-update.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/create-or-update.sh),
  [`connector/wait.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/wait.sh),
  [`connector/diff.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/diff.sh),
  [`tools/connector-diff/diff_report.py`](https://github.com/vdesabou/kafka-docker-playground/blob/master/tools/connector-diff/diff_report.py),
  helpers `validate_connector_config` / `add_connector_config_based_on_environment` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video sessions: [🔌 The sink fails right after it is deployed](/sessions?id=🔌-the-sink-fails-right-after-it-is-deployed), [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
- 🍪 Deep dives: [`topic produce`](/deep-dive-topic-produce.md) for the data the connector reads,
  [`topic consume`](/deep-dive-topic-consume.md) for what a source writes
- 🧠 CLI reference: [playground connector create-or-update](/playground%20connector%20create-or-update),
  [playground connector wait](/playground%20connector%20wait), [playground connector validate](/playground%20connector%20validate),
  [playground connector diff](/playground%20connector%20diff), [playground connector status](/playground%20connector%20status),
  [playground connector show-config](/playground%20connector%20show-config)
