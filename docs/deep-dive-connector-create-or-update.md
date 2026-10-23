# 🍪 Deep dive: `playground connector create-or-update`

The command every example uses to deploy its connector: the JSON config comes from a heredoc, the connector is
created or updated in place, and the command **waits for the connector and its tasks to be RUNNING**, so a broken
config stops the script right there instead of failing silently later. Its companions check a config before you
deploy it (`validate`), compare it with a customer's (`diff`), wait for any state (`wait`), and show what runs
(`status`, `show-config`, `update`). Takes about 15 minutes to read and run.

> [!TIP]
> The video session [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
> picks up where this page stops: the connector is deployed, now why doesn't it work? This page covers getting it
> deployed: how the command works under the hood, its gotchas, a hands-on lab and recipes for support repros.

| You want | Command |
| --- | --- |
| create or update a connector, and fail if it doesn't run | `playground connector create-or-update -c <name> << EOF … EOF` |
| the same, from a customer's file (REST API format accepted) | `playground connector create-or-update -c <name> customer.json` |
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

# a file (path or @path): a customer's config, plain or REST API format
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
- `diff --file` accepts a plain config, the REST API format, or a heredoc as printed by `show-config`. Passwords masked
  by the REST API (`****`, `[hidden]`) are listed as not compared, never as different.
- `diff --defaults` lists the keys set to a non-default value, the keys set to their default (they could be removed),
  and the keys that are not plugin parameters (converters, transforms, worker overrides). Not on CFK.
- `status` on a FAILED connector ends with a hint: `playground connector diagnose --connector <name>` gives the error
  digest, the lag and the next steps.
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
# broken-sink   ✅ RUNNING  0:🛑 FAILED   tasks: org.apache.kafka.connect.errors.ConnectException: Couldn't find or create file '/does/not/exist/output.json' for FileStreamSinkTask
#   … Caused by: java.nio.file.NoSuchFileException: /does/not/exist/output.json
# 🩺 for the error digest, the progress and the next steps, run: playground connector diagnose --connector broken-sink
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
# 📦 the config is in the REST API format ({"name": ..., "config": {...}}): using its "config"
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

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "here is our connector config" (JSON from the UI / REST API) | `create-or-update -c <name> customer.json --validate`: REST API format accepted, every invalid key at once |
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
playground connector wait -c <name> [--state RUNNING|PAUSED|STOPPED|FAILED] [--max-wait 120] [--interval 5]
playground connector diff -c <name> --file <cfg> | --with-connector <other> | --defaults [--json]
playground connector status | show-config [--force-rest-endpoint] | update   [-c <name>]
```

- Create = update: re-run freely. An update prints the changed keys, and keeps PAUSED / STOPPED.
- Waits for the connector **and its tasks** RUNNING: strict in examples, warning in repro models, `--wait` strict
  everywhere, `--no-wait` none. Fully managed: only with `--wait`.
- The environment's settings are added for you: `--dry-run` shows them, `--skip-automatic-connector-config` removes
  them.
- `show-config` = what you sent (`/tmp/config-<name>`). `--force-rest-endpoint` = what runs.
- Sources: [`connector/create-or-update.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/create-or-update.sh),
  [`connector/wait.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/wait.sh),
  [`connector/diff.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/connector/diff.sh),
  helpers `validate_connector_config` / `add_connector_config_based_on_environment` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
- 🍪 Deep dives: [`topic produce`](/deep-dive-topic-produce.md) for the data the connector reads,
  [`topic consume`](/deep-dive-topic-consume.md) for what a source writes
- 🧠 CLI reference: [playground connector create-or-update](/playground%20connector%20create-or-update),
  [playground connector wait](/playground%20connector%20wait), [playground connector validate](/playground%20connector%20validate),
  [playground connector diff](/playground%20connector%20diff), [playground connector status](/playground%20connector%20status),
  [playground connector show-config](/playground%20connector%20show-config)
