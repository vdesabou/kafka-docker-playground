# 🍪 Deep dive: running examples and changing versions (`playground run`)

The commands that start an example and pin its versions: `playground run` turns its flags into environment variables
and runs the example script, `playground re-run` and `playground history` replay a previous run, and
`playground update-version` swaps the Confluent Platform or connector version of the running example without starting
from scratch. This is how you get the customer's exact versions, try a connector build from engineering, or bisect the
version where a behaviour changed. Takes about 15 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session [🎯 Is it fixed in a newer version?](/sessions?id=🎯-is-it-fixed-in-a-newer-version) shows it in 4 minutes: `connector versions`, then `update-version` with `--connector-tag`, a `--connector-zip` build and `--connect-tag`, on the example that runs.
>
> The video session [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags)
> shows the menu, the main flags, `re-run` and `history`. This page goes further: what `run` does under the hood, how
> versions are resolved, what `update-version` can change without a new run, a hands-on lab and recipes for support
> repros.

| You want | Command |
| --- | --- |
| run an example with the default versions | `playground run -f <example.sh>` |
| the customer's Confluent Platform version | `--tag 7.9.1` (every component), `--connect-tag 7.9.1` (connect only) |
| the customer's connector version | `--connector-tag 10.8.4` (from Confluent Hub; `a,b` for an example with two connectors) |
| a connector build from engineering | `--connector-zip /path/to/connector.zip`, or `--connector-jar /path/to/one.jar` |
| the same example on SASL, SSL, Kerberos, RBAC, CFK, Confluent Cloud | `--environment sasl-ssl` (connector examples only) |
| Control Center, ksqlDB, Grafana, kcat… next to it | `--enable-control-center`, `--enable-ksqldb`, `--enable-jmx-grafana`, `--enable-kcat`… |
| DEBUG / TRACE before the connector is created | `--connect-log-level "io.confluent.connect.jdbc=TRACE"` |
| the last run again, same flags | `playground re-run` (menu), or the last line of `playground-run-history` (scripts) |
| another version, keeping the example running | `playground update-version --tag 8.2.0` / `--connect-tag` / `--connector-tag` / `--connector-zip` |
| stop everything, volumes included | `playground stop` |

---

## 1. Mental model (the 3 things to remember)

1. **A run is: stop what runs, turn the flags into environment variables, `bash <example>.sh`.** `playground run`
   checks the flags (known-bad combinations fail **before** anything is stopped), stops the previous example, records
   the run, then executes the script from its folder. The flags only become environment variables of that script:

   | Flag | Variable read by the example (through `scripts/utils.sh`) |
   | --- | --- |
   | `--tag` | `TAG` (default: the `# default tag` line of `scripts/utils.sh`) |
   | `--connect-tag`, `--schema-registry-tag`, `--ksqldb-tag`, `--control-center-tag` | `CP_CONNECT_TAG`, `CP_SCHEMA_REGISTRY_TAG`, `CP_KSQL_TAG`, `CP_CONTROL_CENTER_TAG` |
   | `--connector-tag`, `--connector-zip`, `--connector-jar` | `CONNECTOR_TAG`, `CONNECTOR_ZIP`, `CONNECTOR_JAR` |
   | `--enable-<x>` | `ENABLE_<X>` (docker compose profiles of the environment) |
   | `--environment` | `PLAYGROUND_ENVIRONMENT` |

   So `TAG=8.2.0 bash connect/connect-filestream-sink/filestream-sink.sh` does almost the same thing, and an example
   is plain bash you can read: everything a flag changes is visible in `scripts/utils.sh` and `environment/<env>/start.sh`.

2. **The connector comes from the example's `CONNECT_PLUGIN_PATH`, installed fresh at each run.** `utils.sh` reads
   `CONNECT_PLUGIN_PATH` in the docker compose override of the example (`/usr/share/confluent-hub-components/<owner>-<name>`),
   empties the `confluent-hub/` folder of the repository, and installs each plugin with `confluent-hub install` in a
   throw-away connect container: `latest` by default, `--connector-tag` otherwise (one version per plugin, comma
   separated, in the order of `CONNECT_PLUGIN_PATH`). `--connector-zip` installs your zip instead, `--connector-jar`
   replaces one jar of the installed plugin. The `connect` container mounts that folder. Built-in plugins
   (FileStream, the JDBC and Replicator jars of some images) have no Hub version: there is nothing to pin.

3. **The run is recorded, and everything after it replays the record.** `playground.ini` keeps the example
   (`run.test_file`), the flags (`run.array_flag_list_base64`), the environment and the full docker compose command of
   the environment (`run.docker_command`); `playground-run-history` (repository root) gets one
   `playground run -f <example> <flags>` line per run. `re-run` replays the flags, `update-version` and
   `container recreate` replay the docker compose command with other versions, `stop` replays it with
   `down -v --remove-orphans`, `repro export` reads the history for the run line of a model.

---

## 2. `playground run`: flags and what they do

```bash
# no flag: default CP version, latest connector from Confluent Hub
playground run -f "$PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh"

# the customer's versions
playground run -f "$PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh" --tag 7.9.1 --connector-tag 10.8.4

# connect on another CP version than the broker (an old worker on a new cluster)
playground run -f "$PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh" --connect-tag 7.6.1

# a build from engineering
playground run -f "$PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh" --connector-zip ~/Downloads/confluentinc-kafka-connect-jdbc-10.9.0-SNAPSHOT.zip
playground run -f "$PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh" --connector-jar ~/Downloads/kafka-connect-jdbc-10.9.0-SNAPSHOT.jar

# same example, another security setup, with TRACE before the connector is created
playground run -f "$PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh" --environment sasl-ssl \
  --connect-log-level "io.confluent.connect.jdbc=TRACE"
```

What the run prints, in order:

```text
⛳ Flags used are --tag=8.2.0
🚀 Number of examples ran so far: 363
####################################################
🚀 Executing filestream-sink.sh in dir /…/kafka-docker-playground/connect/connect-filestream-sink
####################################################
…the example's own output…
####################################################
✅ RESULT: SUCCESS for filestream-sink.sh (took: 0min 40sec - )
####################################################
```

then the connector versions and status, and the links to the docs and the source code.

| Exit code | Printed | Meaning |
| --- | --- | --- |
| 0 | `✅ RESULT: SUCCESS` | the example ran to the end |
| 111 | `⏭ RESULT: SKIPPED` | the example refused the combination itself (`exit 111` after a version guard, an unsupported `--environment`) |
| other | `🔥 RESULT: FAILURE` | the example failed; when the same example is also red in CI, its latest CI failure is shown next to yours |

Gotchas:

- **A run stops what was running.** The very first run on a machine kills **every container** (`container kill-all`)
  and sets `playground config container-kill-all-before-run false`; the next runs only `playground stop` the previous
  example. Set it back to `true` if you want a clean slate each time.
- **`-f` takes a path to a `.sh`**: relative paths are accepted (completed with the current folder), `@<path>` too
  (what `<tab>` completion produces). The help says "absolute": that's what the completion and the history store.
- **Bad combinations fail before anything is stopped**: `--enable-legacy-control-center` with CP 8, `--enable-kraft`
  with CP < 7.4 are errors; `--ksqldb-tag` without `--enable-ksqldb`, `--environment` on an example that starts its own
  environment are warnings.
- **Missing credentials fail early** in non-interactive runs: the variables the example needs (from `playground secrets`
  or the environment) are checked before the previous example is stopped.
- **`--environment` only applies to connector examples** that start the environment with
  `PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}`; an example that doesn't support it is skipped
  (exit 111).
- `--connector-tag` and `--connector-zip` are exclusive. `--connector-jar` combines with either: it replaces the jar of
  the installed plugin whose name contains the connector version, and warns when it can't find it.
- On macOS the run line is copied to the clipboard (`playground config clipboard false` to stop it).
- The examples guard unsupported versions themselves: many connector examples `exit 111` when the connector is too old
  for CP 8 (`connect_cp_version_greater_than_8` and `version_gt $CONNECTOR_TAG …` at the top of the script).

---

## 3. Replaying: `re-run`, `history`, the history file

```bash
playground re-run                      # menu with the last example and its flags preselected, 🚀 to run
playground history                     # picker over playground-run-history, the line is editable before it runs
tail -1 playground-run-history         # the last run line, for a script
playground state get run.test_file     # the example of the last run
```

Gotchas:

- **`re-run` and `history` are interactive** (fzf menu, editable prompt): they need a terminal. In a script or an agent,
  run the line from `playground-run-history` with `playground run -f …`.
- **`re-run` replays the flags, not the versions resolved by the last run**: without `--connector-tag`, it installs
  the latest connector of today again, not the one installed last time. Pin the version with a flag to replay exactly.
- The history keeps every run, a repro model's `--cluster-creds` included: it's a local file, don't share it as is.
- `run.test_file` is only updated once the run really starts: cancelling the menu or a bad combination keeps the
  previous example as the current one.

---

## 4. `update-version`: another version, same example

```bash
playground update-version --tag 8.2.0                                # every CP component
playground update-version --connect-tag 7.9.1                        # only connect
playground update-version --connector-tag 10.8.4                     # the connector (a,b for two connectors)
playground update-version --connector-zip ~/Downloads/connector.zip  # a build
playground update-version                                            # menu, with the versions running now
```

How it works:

| Flag | What happens |
| --- | --- |
| `--tag` / `--connect-tag` | the docker compose command of the run is replayed (`container recreate --ignore-current-versions`): only the containers whose image changes are recreated. With `--connect-tag` alone, the other components keep their running version (`Container connect Recreate`, done in about 15 s). A flag equal to the running version is ignored (`--tag=8.3.2 is same as current tag, ignoring...`) |
| `--connector-tag` / `--connector-zip` / `--connector-jar` | the plugin is installed again in `confluent-hub/` (the compose override of the example tells which), then `connect` is restarted and `playground connector versions` prints what's loaded |

Gotchas:

- **The example's script is not run again**: topics, data and connectors stay as they are, only the containers change.
  That's what makes it a bisect tool, and also its limit: a connector config that depends on the version, or data that
  the script creates, is not redone. When in doubt, `playground run` with the new flags.
- **The current versions are read from the running `broker` and `connect` containers**: the example must be up.
- A recreated container loses what was done inside it (`container change-jdk`, files you copied, network rules): see
  the [containers deep dive](/deep-dive-container-lifecycle.md).
- `update-version` doesn't update `playground.ini`'s flags: a `re-run` afterwards goes back to the flags of the last
  `playground run` (`update-version` writes nothing to `playground.ini` nor to `playground-run-history`).
- Built-in plugins (FileStream) have no connector version to pick: the connector entries of the menu are hidden for
  them.

---

## 5. Hands-on lab (≈15 min)

**Step 1: an older CP version**

```bash
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh" --tag 8.2.0
# ⛳ Flags used are --tag=8.2.0
# ✅ RESULT: SUCCESS for filestream-sink.sh (took: 0min 40sec - )
playground status
# connect              Up 41 seconds   confluentinc/cp-server-connect:8.2.0
# broker               Up 41 seconds   confluentinc/cp-server:8.2.0
```

**Step 2: what was recorded**

```bash
tail -1 playground-run-history
# playground run -f /…/connect/connect-filestream-sink/filestream-sink.sh --tag=8.2.0   <- absolute path, flags as --flag=value
playground state get run.test_file
# …/connect/connect-filestream-sink/filestream-sink.sh
```

**Step 3: connect only, on another version**

```bash
playground update-version --connect-tag 8.3.2
# ✨ Loading new version(s) based on flags ⛳ --connect-tag=8.3.2
# 💣 Detected confluent version change, restarting containers
#  Container connect Recreate … Container connect Recreated            <- connect only, about 15 s
playground status
# broker … confluentinc/cp-server:8.2.0   connect … confluentinc/cp-server-connect:8.3.2   schema-registry … 8.2.0
playground connector status
# filestream-sink   ✅ RUNNING  0:🟢 RUNNING
```

**Step 4: every component**

```bash
playground update-version --tag 8.3.2
playground status
# broker … confluentinc/cp-server:8.3.2   (every component on 8.3.2)
playground update-version --tag 8.3.2
# ❗ --tag=8.3.2 is same as current tag, ignoring...
```

**Step 5: a log level set before the connector, by the run**

```bash
playground run -f "$PWD/connect/connect-filestream-sink/filestream-sink.sh" --connect-log-level "org.apache.kafka.connect.file=TRACE"
playground debug log-level get --package org.apache.kafka.connect.file
# {"level":"TRACE","last_modified":1792760406486}        <- set by the run, before the example created its connector
playground container logs -c connect --grep "Writing line to" --no-follow --tail 50
# [2026-10-23 13:00:16,554] TRACE [filestream-sink|task-0] Writing line to /tmp/output.json: {website=…, name=Bailey_Welch, …}
# … one line per record the example produced
```

**Step 6: replay the last run from a script**

```bash
eval "$(tail -1 playground-run-history)"
# ⛳ Flags used are --connect-log-level=org.apache.kafka.connect.file=TRACE        <- the same run, flags included
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer situation | Command |
| --- | --- |
| "we run CP 7.9.1 and connector 10.8.4" | `playground run -f <example> --tag 7.9.1 --connector-tag 10.8.4` |
| "our Connect cluster is older than our brokers" | `--connect-tag <their connect version>` (and `--tag` for the brokers) |
| "is it fixed in the latest connector?" | run with their version, reproduce, then `playground update-version --connector-tag <newer>` and check again |
| "which version broke it?" | keep the example running, `update-version --connector-tag` (or `--tag`) on each candidate: a bisect without re-running the scenario |
| "engineering sent a SNAPSHOT build" | `--connector-zip <zip>` (whole plugin) or `--connector-jar <jar>` (one jar of the installed plugin) |
| "it only fails with SASL_SSL / mTLS / Kerberos" | `--environment sasl-ssl` / `2way-ssl` / `kerberos` on the same example |
| "logs from the very start of the connector" | `--connect-log-level "<package>=TRACE"` (set before the example creates its connector) |
| "the example is skipped" | `⏭ RESULT: SKIPPED`: read the top of the script, a version guard refused the combination (`exit 111`) |
| "does it fail in CI too?" | `playground get-ci-result --test <folder> --logs`: tail and digest of each failing script, plus an HTML report (known causes, last lines, every record, links to the issue and the job) in `/tmp/playground-ci-result` |

In a repro model, write the versions in the run line you share (`playground repro export` takes it from
`playground-run-history`), so the next person reproduces with the same ones.

---

## 7. Cheat sheet

```bash
playground run -f <example.sh> [--tag X] [--connect-tag X] [--connector-tag A[,B]] [--connector-zip zip] [--connector-jar jar] \
  [--environment sasl-ssl|2way-ssl|kerberos|rbac-sasl-plain|cfk|ccloud|…] [--enable-control-center] [--enable-jmx-grafana] [--enable-kcat] \
  [--connect-log-level "<pkg>=TRACE,…"] [-o]
playground re-run                    # menu, last example and flags
playground history                   # picker over playground-run-history
playground update-version [--tag X | --connect-tag X | --connector-tag A[,B] | --connector-zip zip | --connector-jar jar]
playground stop                      # down -v: containers and volumes
```

- A run = check flags, stop the previous example, flags → environment variables, `bash <example>.sh`.
- The connector is installed at each run from the example's `CONNECT_PLUGIN_PATH`: latest unless pinned.
- `playground.ini` + `playground-run-history` record the run; `re-run`, `update-version`, `recreate`, `stop` replay it.
- `update-version` changes containers, not the scenario: the script is not run again.
- Exit codes: 0 success, 111 skipped, anything else failure.
- Sources: [`commands/run.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/run.sh),
  [`commands/re-run.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/re-run.sh),
  [`commands/update-version.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/update-version.sh),
  [`commands/stop.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/stop.sh),
  connector installation in [`scripts/utils.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/utils.sh).

---

**Links**

- 🎬 Video sessions: [🎯 Is it fixed in a newer version?](/sessions?id=🎯-is-it-fixed-in-a-newer-version), [🕹️ Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags)
- 🍪 Deep dives: [containers](/deep-dive-container-lifecycle.md) (what a recreation loses),
  [log levels](/deep-dive-log-levels.md) (`--connect-log-level`), [reproduction models](/deep-dive-reproduction-models.md)
  (the run line of a model)
- 📚 [Start an example](/how-to-use?id=🏎️-start-an-example) in How to Use
- 🧠 CLI reference: [playground run](/playground%20run), [playground re-run](/playground%20re-run),
  [playground update-version](/playground%20update-version), [playground history](/playground%20history),
  [playground stop](/playground%20stop)
