# 🎬 Bite size sessions

Short sessions (2–4 minutes), each about one thing the playground does for you. The narration is typed in the terminal as
`#` comments, so you can pause the video and copy the commands. The sessions that write an HTML report end on it, and
link to a live report so you can click around it yourself.

> [!TIP]
> The shorter clips at the top of the [introduction](/introduction.md) (🍿 See it in action) show one command each. The
> sessions here explain what the output means and what to do next.
>
> To go further on a topic, the [🍪 Deep dives](/deep-dives.md) are the written companions of some sessions: how the
> commands work under the hood, their gotchas, a hands-on lab and recipes for support repros.

| | Session | Needs |
| --- | --- | --- |
| 🕹️ | [Run an example: with the menu or with flags](/sessions?id=🕹️-run-an-example-with-the-menu-or-with-flags) | docker |
| 🎯 | [Is it fixed in a newer version? Swap versions on the running example](/sessions?id=🎯-is-it-fixed-in-a-newer-version) | a running example |
| 🔐 | [The same example under SASL_SSL and RBAC: what the CLI does for you](/sessions?id=🔐-the-same-example-under-sasl_ssl-and-rbac) | docker |
| 🐳 | [Restart or recreate? What a container keeps: an environment variable, another JDK](/sessions?id=🐳-restart-or-recreate-what-a-container-keeps) | a running example |
| 🧪 | [The life of a reproduction model: bootstrap, check, export, import](/sessions?id=🧪-the-life-of-a-reproduction-model) | docker |
| 🩺 | [A sink is RUNNING but writes nothing: diagnose, dead letter queue, replay](/sessions?id=🩺-a-sink-is-running-but-writes-nothing) | a running example |
| 🔌 | [The sink fails right after it is deployed: validate, wait, update in place](/sessions?id=🔌-the-sink-fails-right-after-it-is-deployed) | a running example |
| ⏪ | [The lag of a sink is stuck: follow it, then rewind the sink](/sessions?id=⏪-the-lag-of-a-sink-is-stuck) | a running example |
| 🕵️ | [A connector failed: read the logs, live or from a customer bundle](/sessions?id=🕵️-a-connector-failed-read-the-logs-live-or-from-a-customer-bundle) | a running example |
| 🧬 | [TRACE on a running connector, without a restart](/sessions?id=🧬-trace-on-a-running-connector-without-a-restart) | a running example |
| 🔀 | [What does this transform chain (SMT) do to a record?](/sessions?id=🔀-what-does-this-transform-chain-do-to-a-record) | a running example |
| 🧑‍💻 | [The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version) | nothing |
| 🐞 | [A breakpoint in a running connector: remote debugging](/sessions?id=🐞-a-breakpoint-in-a-running-connector-remote-debugging) | a running example |
| 🧵 | [A connector looks stuck: analyze thread dumps](/sessions?id=🧵-a-connector-looks-stuck-analyze-thread-dumps) | nothing (`--sample`) |
| ♻️ | [Long GC pauses or a memory leak: analyze GC logs](/sessions?id=♻️-long-gc-pauses-or-a-memory-leak-analyze-gc-logs) | nothing (`--sample`) |
| 🛩️ | [A slow connector: where does the task time go?](/sessions?id=🛩️-a-slow-connector-where-does-the-task-time-go) | nothing (`--sample`) |
| ✂️ | [Records vanish, a task hangs: what does the code do? jscissors, call by call](/sessions?id=✂️-records-vanish-a-task-hangs-what-does-the-code-do) | a running example |
| 🅾️ | [Oracle XStream CDC lags or is idle: analyze the orclcdc_diag report](/sessions?id=🅾️-oracle-xstream-cdc-lags-or-is-idle) | nothing (`--sample`) |
| ☸️ | [What is wrong in this CFK cluster? Analyze a support bundle](/sessions?id=☸️-what-is-wrong-in-this-cfk-cluster) | nothing (`--sample`) |
| 📨 | [Produce realistic test data](/sessions?id=📨-produce-realistic-test-data) | a running environment |
| 📥 | [Read a topic: the last records, one offset, from a time, as JSON](/sessions?id=📥-read-a-topic) | a running environment |
| 🪛 | [A producer gets RecordTooLargeException: a topic config, reproduced and fixed](/sessions?id=🪛-a-producer-gets-recordtoolargeexception) | a running environment |
| 🔰 | [Schema not found after a cleanup: a refused version, soft vs permanent delete](/sessions?id=🔰-schema-not-found-after-a-cleanup) | a running environment |
| 📈 | [Is version Y slower? Benchmark two versions](/sessions?id=📈-is-version-y-slower-benchmark-two-versions) | a running example |
| 🐌 | [A slow or broken network, on purpose: degrade and block traffic](/sessions?id=🐌-a-slow-or-broken-network-on-purpose) | a running example |
| 🚚 | [Move a self-managed connector to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed) | Confluent Cloud, AWS credentials |
| 🏗️ | [Deploy a fully managed connector with Terraform](/sessions?id=🏗️-deploy-a-fully-managed-connector-with-terraform) | Confluent Cloud, terraform |
| 👤 | [A fully managed connector with a service account loses an ACL: reproduce it, diagnose it](/sessions?id=👤-a-fully-managed-connector-with-a-service-account-loses-an-acl) | Confluent Cloud |

## 🕹️ Run an example: with the menu or with flags

New to the playground? Start here. `playground run` runs any example: without arguments it opens a menu that guides you
through the options of the example, and `playground run -f <example> <flags>` runs it directly, with the same options as
flags.

<video src="videos/session-run.mp4" poster="images/sessions/run.png" controls playsinline width="100%"></video>

**In this session**

- the menu: pick a category, find an example by typing a few words, then the options of that example, group by group
- versions: Confluent Platform (`--tag`, or one component only), connector (`--connector-tag`, `--connector-zip`,
  `--connector-jar`); both version pickers show what changed in the highlighted version, from the docs.confluent.io
  changelogs
- add-ons toggled on and off (Grafana, kcat, Control Center, ksqlDB...), several at once with `<tab>`
- a bad combination (legacy Control Center with CP 8) blocks 🚀 in the menu, and is refused before anything is stopped
  with `-f`
- the same example under another security environment (`--environment sasl-ssl`), another connector version, DEBUG logs
  for the connector (`--connect-log-level`)
- the end of the run: the last connector versions with their release notes, and a hint when a newer patch of the CP
  version is published (`playground cp-changelog --from <version>` lists its changes)
- `playground re-run`, `playground history`, `-o` to open the example files, `playground secrets set`

**Commands**

```bash
# the menu
playground run

# no menu: the example (absolute path, <tab> completion opens a picker) and the flags
playground run -f $PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh --tag 8.2.0 --connector-tag 10.8.12 --enable-jmx-grafana --enable-kcat
playground run -f $PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh --environment sasl-ssl --connector-tag 10.8.4 --connect-log-level io.confluent.connect.jdbc=DEBUG

playground re-run      # the last example again, same flags
playground history     # pick a previous run, edit its flags, run it
playground cp-changelog --from 8.2.0   # what changed in Confluent Platform since 8.2.0 (--grep, --security, --component)
```

> [!TIP]
> Each run stops what was running before starting the example (`playground config container-kill-all-before-run false`
> to only stop the previous example).

**Links**

- 🍪 Deep dive: [running examples and changing versions: under the hood, hands-on lab and repro recipes](/deep-dive-run-and-versions.md)
- 📚 [Start an example](/how-to-use?id=🏎️-start-an-example), [The playground run menu](/how-to-use?id=🕹️-the-playground-run-menu)
- 🧠 CLI reference: [playground run](/playground%20run), [playground re-run](/playground%20re-run),
  [playground history](/playground%20history)

## 🎯 Is it fixed in a newer version?

The customer runs the JDBC sink 10.8.4 on CP 8.2.0. Is the bug fixed in the latest patch? In the build engineering just
sent? With a newer Connect worker? `playground update-version` swaps the connector or Confluent Platform version of the
example that runs, without running it again: the topics, the data and the connectors stay, so you can bisect a version
in a few commands.

<video src="videos/session-versions.mp4" poster="images/sessions/versions.png" controls playsinline width="100%"></video>

**In this session**

- `connector versions`: the CP version and the connector version that run, the last versions on Confluent Hub with
  their release notes, and whether yours is the latest
- `connector-plugin changelog --from <theirs> --grep <symptom>`: is the bug fixed in a newer version, and in which one
- `update-version --connector-tag`: the plugin installed again, `connect` restarted, the connector back to `RUNNING`
  with the same config: the example script is not run again
- `update-version --connector-zip`: a build from engineering (the whole plugin), checked by producing one more record and
  counting the rows in PostgreSQL; `--connector-jar` replaces a single jar of the installed plugin
- `cp-changelog --from 8.2.0 --to 8.3.2 --component kafka`: what changed in Connect (and the other community
  components) between two CP versions
- `update-version --connect-tag`: only `connect` is recreated, the brokers keep their version (an older or newer
  Connect cluster than the brokers); `--tag` moves every component
- `update-version` writes nothing to the run history: a `re-run` goes back to the flags of the last `playground run`

**Commands**

```bash
# the customer's versions (off camera)
playground run -f $PWD/connect/connect-jdbc-postgresql-sink/postgres-sink.sh --tag 8.2.0 --connector-tag 10.8.4

playground connector versions                       # what runs, and the latest on Confluent Hub (with release notes)
playground connector-plugin changelog --connector-plugin confluentinc/kafka-connect-jdbc --from 10.8.4 --to 10.8.12 --grep 'sensitive|redact'
playground update-version --connector-tag 10.8.12   # another connector version, the example is not run again
playground connector wait --connector postgres-sink --max-wait 120
playground update-version --connector-zip /tmp/engineering-build/confluentinc-kafka-connect-jdbc-10.9.9.zip   # or --connector-jar
playground cp-changelog --from 8.2.0 --to 8.3.2 --component kafka --grep 'kafka.connect|connect '   # what changed in Connect
playground update-version --connect-tag 8.3.2       # connect only (--tag: every component)
playground status
playground update-version                           # no flag: a menu with the versions running now
```

**Links**

- 🍪 Deep dive: [running examples and changing versions: under the hood, hands-on lab and repro recipes](/deep-dive-run-and-versions.md)
- 📚 [Specify versions](/how-to-use?id=🪄-specify-versions)
- 🧠 CLI reference: [playground update-version](/playground%20update-version), [playground connector versions](/playground%20connector%20versions),
  [playground connector-plugin changelog](/playground%20connector-plugin%20changelog), [playground cp-changelog](/playground%20cp-changelog)

## 🔐 The same example under SASL_SSL and RBAC

"It works in dev, not in our SSL cluster", "the connector gets `TopicAuthorizationException`": run the same example
under the customer's security setup with one flag. The CLI then talks to the secured cluster for you: same `topic
consume`, same `connector` commands, security keys added to the connector config. Then remove a role binding to
reproduce the authorization error.

<video src="videos/session-secured-environments.mp4" poster="images/sessions/secured-environments.png" controls playsinline width="100%"></video>

**In this session**

- `playground run -f <example> --environment sasl-ssl`: every environment is plaintext plus one compose file
  (listeners, JAAS, keystores), the example script does not change
- the CLI reads `run.environment`: `topic produce` / `topic consume` use the client config of the environment, the
  Connect REST calls go to `https` with the client certificate
- `container get-properties -c connect`: what the worker really loaded (`SASL_SSL`, `listeners=https://0.0.0.0:8083`)
- `connector create-or-update --dry-run`: the security keys added when the connector opens its own connection
  (`*.converter.schema.registry.url` becomes `https` + keystore / truststore)
- a `kafka-*` tool run by hand without the client config fails on the TLS listener (often `OutOfMemoryError: Java heap
  space`), and works with `--command-config`
- `--environment rbac-sasl-plain`: connectors run as `connectorSA`; delete its `ResourceOwner` role binding on `Topic:*`,
  restart, `TopicAuthorizationException`; create it back, restart, `RUNNING`

**Commands**

```bash
playground run -f $PWD/connect/connect-filestream-sink/filestream-sink.sh --environment sasl-ssl
playground state get run.environment
playground topic produce -t filestream --nb-messages 3 --value '{"id": %g}'
playground topic consume -t filestream --min-expected-messages 8 --timeout 60
playground container get-properties -c connect | grep -E 'security.protocol|sasl.mechanism|listeners'
playground connector create-or-update -c filestream-sink --dry-run < /tmp/filestream-avro.json   # the security keys added for you
playground container exec -c connect --command 'kafka-topics --bootstrap-server broker:9092 --command-config /etc/kafka/secrets/client_without_interceptors.config --list'

# RBAC, and an authorization error on purpose
playground run -f $PWD/connect/connect-filestream-sink/filestream-sink.sh --environment rbac-sasl-plain
playground rbac role-binding list --principal User:connectorSA
playground rbac role-binding delete --principal User:connectorSA --role ResourceOwner --resource 'Topic:*'
playground connector restart -c filestream-sink
playground connector wait -c filestream-sink --state FAILED --max-wait 180   # TopicAuthorizationException
playground rbac role-binding create --principal User:connectorSA --role ResourceOwner --resource 'Topic:*'
playground connector restart -c filestream-sink
playground connector wait -c filestream-sink --max-wait 180
```

**Links**

- 🍪 Deep dive: [secured environments: under the hood, hands-on lab and repro recipes](/deep-dive-secured-environments.md)
- 👾 [Environments](/content?id=🔐-environments)
- 🧠 CLI reference: [playground run](/playground%20run), [playground rbac role-binding](/playground%20rbac%20role-binding),
  [playground container get-properties](/playground%20container%20get-properties)

## 🐳 Restart or recreate? What a container keeps

The customer says "it only fails on our workers: Java 17, and these JVM options". Build that worker on the example you
run, without editing a compose file: another JDK in the `connect` container, an environment variable, and see which
command keeps what. Restart, recreate and a new container are three different things, and the order of the commands
matters.

<video src="videos/session-container-lifecycle.mp4" poster="images/sessions/container-lifecycle.png" controls playsinline width="100%"></video>

**In this session**

- `container exec`: one command inside the container, as the image user, without remembering container names
- `container change-jdk`: Azul Zulu 17 installed as root inside `connect`, then a restart (`java -version` shows it)
- `container restart` keeps the container: the JDK, the files you copied and the logs stay (network rules from
  `debug block-traffic` / `degrade-traffic` don't)
- `container recreate` only rebuilds the containers whose definition changed: `Container connect Running`, nothing done,
  so it is not a way to get a clean container
- `container set-environment-variables` builds a **new** container with your variables (`KAFKA_HEAP_OPTS`): Java 17 is
  gone. Set the variables first, then change the JDK, copy files or degrade traffic
- the next `recreate` replays the original command: the variables are gone too, and the connector comes back on its own
  (its config and offsets live in Kafka)

**Commands**

```bash
playground container exec -c connect --command 'java -version 2>&1 | head -1'
playground container change-jdk -c connect --version 17
playground container restart -c connect      # keeps the JDK
playground container recreate                # nothing changed in the definition: nothing done
playground container set-environment-variables -c connect --env "KAFKA_HEAP_OPTS: -Xms1G -Xmx2G"   # a new container: Java 17 is gone
playground container exec -c connect --command 'echo "KAFKA_HEAP_OPTS=$KAFKA_HEAP_OPTS"'
playground container recreate                # the original command again: the variables are gone too
playground connector wait --connector postgres-sink --max-wait 120
```

Recorded on the example `connect/connect-jdbc-postgresql-sink/postgres-sink.sh`.

**Links**

- 🍪 Deep dive: [containers: under the hood, hands-on lab and repro recipes](/deep-dive-container-lifecycle.md)
- 🧠 CLI reference: [playground container exec](/playground%20container%20exec), [playground container change-jdk](/playground%20container%20change-jdk),
  [playground container restart](/playground%20container%20restart), [playground container recreate](/playground%20container%20recreate),
  [playground container set-environment-variables](/playground%20container%20set-environment-variables)

## 🧪 The life of a reproduction model

A reproduction model is an example rewritten to show one problem, so that anyone can reproduce it with a single
`playground run`. Scaffold it from the closest example, build the scenario, run it, make sure it holds no secret, and
hand it to a colleague as one bundle that they import and run.

<video src="videos/session-repro-models.mp4" poster="images/sessions/repro-models.png" controls playsinline width="100%"></video>

**In this session**

- `repro bootstrap -f <absolute path> -d "<case> <symptom>" --no-run`: the model and its own docker compose override,
  without menus, editor or run
- what bootstrap adds to a plain copy: a header (author, 🔮 ticket link from the 6 leading digits, documentation,
  `💬 comments:` for expected vs actual), symlinks to the support files of the public example
- edit the scenario, then `playground run -f <model>`: a model runs like an example (`create-or-update` warns instead of
  stopping when the connector is not RUNNING)
- `repro check`: a credential value or a token format blocks (exit 1, file and line, never the value), emails and
  public IPs only warn
- `repro export --dry-run`, then `repro export`: the run line from the history, symlinks stored as content, a manifest
  with credential names and sha256
- `repro import --dry-run`, then `repro import`: new / identical / conflicting files, the model becomes the current one,
  and the line to run it

**Commands**

```bash
playground repro bootstrap -f $PWD/connect/connect-filestream-sink/filestream-sink.sh -d '000000 bite size session' --no-run
m=$PWD/reproduction-models/connect-connect-filestream-sink/filestream-sink-repro-000000-bite-size-session.sh
# edit the scenario and the 💬 comments: block, then
playground run -f $m
playground repro check -f $m                 # exit 1 on a credential: file and line, never the value
playground repro export -f $m --dry-run
playground repro export -f $m --output /tmp/kdp-session-repro
playground repro import -f /tmp/kdp-session-repro/playground_repro_*.tgz --dry-run
playground repro import -f /tmp/kdp-session-repro/playground_repro_*.tgz
```

**Links**

- 🍪 Deep dive: [reproduction models: under the hood, hands-on lab and repro recipes](/deep-dive-reproduction-models.md)
- 🧰 [Reproduction toolkit](/reusables.md)
- 🧠 CLI reference: [playground repro bootstrap](/playground%20repro%20bootstrap), [playground repro check](/playground%20repro%20check),
  [playground repro export](/playground%20repro%20export), [playground repro import](/playground%20repro%20import)

## 🩺 A sink is RUNNING but writes nothing

The connector is `RUNNING`, its status shows no error, but nothing reaches the destination. One command says why, the dead
letter queue shows which records failed and the root cause, and once the cause is fixed the records are replayed.

<video src="videos/session-dlq.mp4" poster="images/sessions/dlq.png" controls playsinline width="100%"></video>

**In this session**

- `connector diagnose`: status, digest of the ERROR records, consumer lag and next steps, in one call
- `errors.tolerance=all`: why the task does not fail, and where the records went
- `topic dlq inspect`: records grouped by error, with the root cause and the original topic / partition / offsets
- fix the cause, then `topic dlq replay` (dry run first) and check that the sink caught up

**Commands**

```bash
playground connector diagnose --connector filestream-sink
playground topic dlq inspect --connector filestream-sink     # or --topic <dlq>, --grep, --json
playground topic dlq replay --connector filestream-sink --dry-run
playground topic dlq replay --connector filestream-sink      # --to <topic> to replay elsewhere
playground connector show-lag --connector filestream-sink --max-wait 120
```

Recorded on the example `other/reprocess-dlq-messages-with-sink-connector/replay-dlq-messages-with-playground.sh`
(schema-registry stopped while a FileStream sink converts Avro records).

**Links**

- 🍪 Deep dive: [`connector diagnose` and the dead letter queue: under the hood, hands-on lab and repro recipes](/deep-dive-connector-troubleshooting.md)
- 🧠 CLI reference: [playground connector diagnose](/playground%20connector%20diagnose),
  [playground topic dlq inspect](/playground%20topic%20dlq%20inspect), [playground topic dlq replay](/playground%20topic%20dlq%20replay)

## 🔌 The sink fails right after it is deployed

A customer sends the config of their connector: "it fails right after we deploy it". `playground connector create-or-update`
deploys it the way every example does, takes the file as it comes from the REST API, and waits for the connector **and its
tasks** to be `RUNNING`: a config that doesn't run stops the script right there, with the stack trace.

<video src="videos/session-create-or-update.mp4" poster="images/sessions/create-or-update.png" controls playsinline width="100%"></video>

**In this session**

- a customer's config in the REST API format (`{"name": ..., "config": {...}}`) deployed as is: the outer name is ignored
- `--validate`: the plugin checks every key at once (types, required keys, values), but not paths or hostnames
- the wait: the first `FAILED` task stops it with its stack trace (`NoSuchFileException`), exit code 1
- a failure on purpose for a reproduction: `--no-wait`, then `connector wait --state FAILED`, no `sleep`
- create = update: `--dry-run` shows the changed keys and the request, then the same command updates the connector in place

**Commands**

```bash
playground connector create-or-update -c broken-sink --validate /tmp/customer-connector.json   # stops at the first FAILED task, exit 1
playground connector create-or-update -c broken-sink --no-wait /tmp/customer-connector.json    # a failure on purpose
playground connector wait -c broken-sink --state FAILED --max-wait 60
playground connector create-or-update -c broken-sink --dry-run /tmp/customer-connector-fixed.json   # the changed keys
playground connector create-or-update -c broken-sink /tmp/customer-connector-fixed.json             # updated in place
```

Recorded on the example `connect/connect-filestream-sink/filestream-sink.sh`, with the customer's config in the REST API
format (`{"name": ..., "config": {...}}`).

**Links**

- 🍪 Deep dive: [`connector create-or-update`: under the hood, hands-on lab and repro recipes](/deep-dive-connector-create-or-update.md)
- 🧠 CLI reference: [playground connector create-or-update](/playground%20connector%20create-or-update),
  [playground connector wait](/playground%20connector%20wait), [playground connector validate](/playground%20connector%20validate)

## ⏪ The lag of a sink is stuck

"The lag of our sink is stuck at 20." Read the lag where a sink keeps it (its consumer group), find why it doesn't move,
follow it back to 0, then write the last records again by moving the sink back in its topic, without touching the example.

<video src="videos/session-offsets-and-lag.mp4" poster="images/sessions/offsets-and-lag.png" controls playsinline width="100%"></video>

**In this session**

- a sink's offsets live in the consumer group `connect-<connector>`: `consumer-group describe` shows the lag and the members
- `connector show-lag` checks the connector first: a paused sink keeps its place in the group, consumes nothing, and fails
  the check after 60 s
- lag and offsets are **committed** values: after the resume, the lag stays at 20 until the next commit
  (`offset.flush.interval.ms`, 60 s), then drops to 0
- `connector offsets get`: the same position through the Connect offsets API (KIP-875), sources included
- Kafka refuses to reset the group of a running sink; to go back N records or to a date: `connector stop`,
  `consumer-group reset-offsets` (`--dry-run` first), `connector resume`
- the last 3 records are written again: at least once, duplicates but no loss

**Commands**

```bash
playground consumer-group describe --group connect-filestream-sink
playground connector show-lag --connector filestream-sink --interval 5 --max-wait 30
playground connector resume --connector filestream-sink
playground connector show-lag --connector filestream-sink --interval 5 --max-wait 90
playground connector offsets get --connector filestream-sink

# write the last 3 records again
playground connector stop --connector filestream-sink
playground consumer-group reset-offsets --group connect-filestream-sink --topic filestream --shift-by -3 --dry-run
playground consumer-group reset-offsets --group connect-filestream-sink --topic filestream --shift-by -3
playground connector resume --connector filestream-sink
```

Recorded on the example `connect/connect-filestream-sink/filestream-sink.sh` (connector paused, 20 more records produced).

**Links**

- 🍪 Deep dive: [offsets and lag: under the hood, hands-on lab and repro recipes](/deep-dive-offsets-and-lag.md)
- 🧠 CLI reference: [playground connector show-lag](/playground%20connector%20show-lag),
  [playground connector offsets get](/playground%20connector%20offsets%20get),
  [playground consumer-group describe](/playground%20consumer-group%20describe),
  [playground consumer-group reset-offsets](/playground%20consumer-group%20reset-offsets)

## 🕵️ A connector failed: read the logs, live or from a customer bundle

The task is `FAILED` and the answer is somewhere in a worker log of thousands of lines. One flag turns the live log into a
digest of the ERROR records with their root cause, two more give the raw lines or wait for one, and the same digest works
offline on the support bundle a customer sent.

<video src="videos/session-container-logs.mp4" poster="images/sessions/container-logs.png" controls playsinline width="100%"></video>

**In this session**

- `container logs --errors`: ERROR/FATAL records only, stack traces collapsed to the `Caused by:` chain and 3 frames of
  the deepest cause; read the last `Caused by:` first (`Unknown magic byte!`: an AvroConverter on records that are not Avro)
- the same failure after a restart is one finding, counted (`ERROR x2`), with its first and last seen lines
- `--grep` and `--no-follow` for the raw lines; the trap: `--grep` and `--since` alone follow the log forever
- `--wait-for-log` instead of a `sleep` in a repro, and why it matches old lines too
- `playground analyze logs` on a `.zip` bundle: one digest per file, `--include-warnings`, `--max-findings` per file

**Commands**

```bash
playground container logs -c connect --errors --since 10m
playground container logs -c connect --grep 'Unknown magic byte' --no-follow
playground container logs -c connect --wait-for-log 'Unknown magic byte' --max-wait 30
playground analyze logs --sample support_bundle                 # or -f <file|folder|.zip|.tar.gz>
playground analyze logs --sample support_bundle --include-warnings --max-findings 3
```

Recorded on the example `connect/connect-filestream-sink/filestream-sink.sh`, plus a connector `bad-sink` with an
AvroConverter on JSON records.

**Links**

- 🍪 Deep dive: [`container logs` and `analyze logs`: under the hood, hands-on lab and repro recipes](/deep-dive-container-logs.md)
- 🧠 CLI reference: [playground container logs](/playground%20container%20logs), [playground analyze logs](/playground%20analyze%20logs)

## 🧬 TRACE on a running connector, without a restart

"The task failed" is rarely enough: you want the request that failed, the record that broke it, what the transforms did
to it. Raise the log level of the connector's packages on the running worker, reproduce, read the new lines, then put it
back. No restart, no log4j file to edit.

<video src="videos/session-log-levels.mp4" poster="images/sessions/log-levels.png" controls playsinline width="100%"></video>

**In this session**

- `debug log-level get`: a `404 Logger … not found` only means the package has no level of its own (it inherits `INFO`)
- `debug log-level set --level TRACE` on the package of `connector.class`: live, for the package and everything below it,
  on every worker on CP 7.7+ (`scope=cluster`), then one TRACE line per record in the log
- `connector log-level`: the connector's package + `RestService` (schema registry requests), `TransformationChain` (records
  before and after each SMT), `WorkerSinkTask` / `WorkerSourceTask`; a level already set is skipped
- back to normal is `--level INFO`, there is no reset; TRACE logs can hold records: check them before sharing
- a worker restart forgets every level: `CONNECT_LOG4J_LOGGERS` in the compose override for levels that must survive it

**Commands**

```bash
playground debug log-level get --package org.apache.kafka.connect.file
playground debug log-level set --package org.apache.kafka.connect.file --level TRACE
playground container logs -c connect --grep 'Writing line' --no-follow
playground connector log-level --connector filestream-sink --level TRACE    # + RestService, TransformationChain, WorkerSinkTask
playground connector log-level --connector filestream-sink --level INFO     # back to normal, there is no reset
```

Recorded on the example `connect/connect-filestream-sink/filestream-sink.sh`.

**Links**

- 🍪 Deep dive: [log levels: under the hood, hands-on lab and repro recipes](/deep-dive-log-levels.md)
- 🧠 CLI reference: [playground debug log-level](/playground%20debug%20log-level), [playground connector log-level](/playground%20connector%20log-level)

## 🔀 What does this transform chain do to a record?

A customer sends a connector config with five transforms: records land in the wrong table, or the task fails in an SMT. The
SMT tester runs the chain step by step on a real record, with the classes and versions of the running worker.

<video src="videos/session-smt-test.mp4" poster="images/sessions/smt-test.png" controls playsinline width="100%"></video>

**In this session**

- the value, schema and topic after each step: a field renamed, a field added, the topic routed
- a `TimestampConverter` on a field that does not exist: a **silent no-op**, no error
- the step that throws, with its config and its error
- comparing CP versions (`--cp-version`), SMTs that are not in the worker (`--smt-plugin`, `--smt-jar`)

**Commands**

```bash
# the chain of a config on stdin, on a real record of a topic
playground connector smt test --from-topic orders --offset 0 < transforms.json

# the chain of a running connector, on a record of your own
playground connector smt test --connector my-sink --record '{"topic":"orders","value":{"id":1,"name":"foo"}}'
```

**Links**

- 🍪 Deep dive: [`connector smt test` under the hood, hands-on lab and repro recipes](/deep-dive-connector-smt-test.md)
- 🌐 <a href="reports/smt-test.html" target="_blank" rel="noopener">An SMT test report</a> (another chain, CP 7.9.0 vs 8.3.2: click around)
- 🧠 CLI reference: [playground connector smt test](/playground%20connector%20smt%20test)

## 🧑‍💻 The source code of a connector at the customer's version

A customer runs the JDBC sink 10.8.4: what does `batch.size` do, what is its default, and what changed since? The answers
are in the docs of the key and in the code at their exact tag, not on the main branch.

<video src="videos/session-sourcecode.mp4" poster="images/sessions/sourcecode.png" controls playsinline width="100%"></video>

**In this session**

- the docs of a config key, offline: doc, type, default, since when, values used in the examples
- the GitHub tree of a connector at an exact version, and the comparison of two versions
- a local checkout of that tag, to grep it
- fully managed connectors (resolved to their `v<version>-cloud` tag), `--open`, `--compile`

**Commands**

```bash
playground connector-plugin config-key --key batch.size --connector-class io.confluent.connect.jdbc.JdbcSinkConnector
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --only-show-url
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --connector-tag 10.9.9 --only-show-url
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --checkout-only
```

**Links**

- 🍪 Deep dive: [`connector-plugin`: versions, config keys, source code, jars](/deep-dive-connector-plugin.md)
- 🧠 CLI reference: [playground connector-plugin config-key](/playground%20connector-plugin%20config-key),
  [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode)

## 🐞 A breakpoint in a running connector: remote debugging

The logs are not enough: you want to see what the connector does with a record. The `connect` container always listens
for a Java debugger on port `5005`: get the code of the version that runs, attach a debugger, set a breakpoint, and inspect
the records as the connector sees them.

<video src="videos/session-remote-debugging.mp4" poster="images/sessions/remote-debugging.png" controls playsinline width="100%"></video>

**In this session**

- the version of the connector that runs, and its code at that tag, to know where to stop
- `jdb`, the debugger of the JDK, attached to `localhost:5005`, a breakpoint in `JdbcSinkTask.put` before the records are written
- `where`, `list`, `locals`, `print`: the call stack from the Connect framework, the source, the batch, the value of a record
- the same in Visual Studio Code (and IntelliJ IDEA): an attach configuration on `127.0.0.1:5005`

**Commands**

```bash
playground connector versions
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.9.9 --checkout-only
jdb -attach localhost:5005 -sourcepath /tmp/connector-plugin-sourcecode/kafka-connect-jdbc-10.9.9/src/main/java
# in jdb: stop at io.confluent.connect.jdbc.sink.JdbcSinkTask:87, then where, list, locals, print first.value(), clear, cont

# another container than connect (broker, schema-registry...): also prints the launch.json entry for VS Code
playground debug enable-remote-debugging -c broker
```

> [!WARNING]
> `stop at` suspends every thread of the worker: keep the pause short (the worker and consumer groups time out), then
> `clear` the breakpoint and `cont`.

**Links**

- 📚 Step by step with Visual Studio Code: [✨ Remote debugging](/reusables?id=✨-remote-debugging) in the Reproduction toolkit
- 🧠 CLI reference: [playground debug enable-remote-debugging](/playground%20debug%20enable-remote-debugging),
  [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode)

## 🧵 A connector looks stuck: analyze thread dumps

The task is `RUNNING`, but no record moves and there is no error in the logs. Three thread dumps of the worker, a few
seconds apart, show which threads are stuck, blocked or burning CPU.

<video src="videos/session-thread-dump.mp4" poster="images/sessions/thread-dump.png" controls playsinline width="100%"></video>

**In this session**

- the 3 ways to run it: live on a running example, on dumps sent by a customer, on a sample shipped with the playground
- reading the findings, most severe first: deadlock, lock contention, stuck Connect task, CPU-hot thread, leaking thread pool
- from the stuck frame to the code: the connector source code at the customer's version
- the HTML report to share

**Commands**

```bash
# live, on a running example: 3 dumps 5 s apart, then the analysis
playground analyze thread-dump -c connect

# on dumps from a customer: one -f per dump of the same JVM
playground analyze thread-dump -f dump1.txt -f dump2.txt -f dump3.txt

# on the sample used in the session
playground analyze thread-dump --sample deadlock_jdk21 --output-dir /tmp/thread-dump
```

**Links**

- 🍪 Deep dive: [JVM diagnostics: which collector, which analyzer](/deep-dive-jvm-diagnostics.md)
- 🌐 <a href="reports/thread-dump.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze thread-dump](/playground%20analyze%20thread-dump)
- 🔗 Next step: [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode)

## ♻️ Long GC pauses or a memory leak: analyze GC logs

The worker freezes, tasks get rebalanced, the heap keeps growing. Every GC pause stops all the threads of the JVM: the GC
log says how long each pause was, why it happened, and how full the heap was before and after.

<video src="videos/session-gc-logs.mp4" poster="images/sessions/gc-logs.png" controls playsinline width="100%"></video>

**In this session**

- live on a running example, on GC logs from a customer (JDK 7 to 21, any collector), on a sample
- health score, pause times and distribution, live set, causes, longest pauses
- recommendations with the JVM flag to try (`-Xmx`, `-XX:G1ReservePercent`)
- a heap floor that keeps rising = a leak: the next step is a heap dump

**Commands**

```bash
playground analyze gc-logs -c connect
playground analyze gc-logs -f gc.log                       # a file, or a folder of rotated logs
playground analyze gc-logs --sample jdk21_g1_kafka_real --output-dir /tmp/gc-logs
```

**Links**

- 🍪 Deep dive: [JVM diagnostics: which collector, which analyzer](/deep-dive-jvm-diagnostics.md)
- 🌐 <a href="reports/gc-logs.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze gc-logs](/playground%20analyze%20gc-logs), next step [playground analyze heap-dump](/playground%20analyze%20heap-dump)

## 🛩️ A slow connector: where does the task time go?

The connector works, but it is slow. Is it the database, the network, Kafka, a lock, the converters, or the connector code
itself? Java Flight Recorder samples what every thread does, with almost no overhead, and the digest answers with numbers.

<video src="videos/session-flight-recorder.mp4" poster="images/sessions/flight-recorder.png" controls playsinline width="100%"></video>

**In this session**

- a recording over JMX on a running example (no restart), or a `.jfr` from a customer, or a sample
- task time by state: running, blocked on network I/O, in the Kafka client
- CPU by layer (connector, converters, Kafka client, drivers), hot methods, network calls by remote, allocation
- what was checked and found normal (lock contention, exceptions, GC pauses)

**Commands**

```bash
playground analyze flight-recorder -c connect --duration 60s --connector <connector>
playground analyze flight-recorder -f rec.jfr              # jcmd <pid> JFR.start duration=60s filename=rec.jfr
playground analyze flight-recorder --sample jdbc_postgres_sink --output-dir /tmp/flight-recorder
```

**Links**

- 🍪 Deep dive: [JVM diagnostics: which collector, which analyzer](/deep-dive-jvm-diagnostics.md)
- 🌐 <a href="reports/flight-recorder.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze flight-recorder](/playground%20analyze%20flight-recorder)

## ✂️ Records vanish, a task hangs: what does the code do?

The sink is `RUNNING`, rows are missing in the database, and there is no error in the logs. A thread dump says where the
threads are, a flight recording where the time goes on average: jscissors records **what the methods you pick receive,
return and throw, and how long each call takes**. A java agent is loaded in the running worker: no restart, no debugger
that freezes it, no log line to add and no connector to rebuild.

<video src="videos/session-jscissors.mp4" poster="images/sessions/jscissors.png" controls playsinline width="100%"></video>

**In this session**

- a JDBC sink with `errors.tolerance=all` and no dead letter queue: 10 orders sent, 8 rows, no ERROR in the logs
- `--only-failed` on the converter: every call is counted, only the 2 that threw are kept, with their arguments (plain
  JSON bytes on an avro topic: a legacy producer)
- the route to postgres cut on purpose: the task stays `RUNNING`, the lag grows. At `stop`, the call still running, for
  how long, and the batch it holds (its first offset)
- a regex for several classes and methods, `--slower-than`, `--operation EXCEPTION_THREADS`, `--duration`, `--restart`
- what is masked (passwords, tokens) and what is not (record values): read the report before sharing it

**Commands**

```bash
# which records does the converter reject? only the calls that throw, with their arguments
playground debug jscissors -c connect --class io.confluent.connect.avro.AvroConverter --method toConnectData --only-failed --action start
playground debug jscissors -c connect --action stop --output-dir /tmp/jscissors     # restores the classes, copies, analyzes

# where does the task hang, since when, on which records?
playground debug jscissors -c connect --class 'io.confluent.connect.jdbc.sink.(JdbcDbWriter|BufferedRecords)' --method 'write|flush' --action start
playground debug jscissors -c connect --action stop --output-dir /tmp/jscissors

# start, wait, stop and analyze in one command; the sample, without docker
playground debug jscissors -c connect --class <class> --method <method> --duration 60s
playground analyze jscissors --sample filestream_sink_bad_json --output-dir /tmp/jscissors
```

Recorded on the example `connect/connect-jdbc-postgresql-sink/postgres-sink.sh`.

**Links**

- 🍪 Deep dive: [JVM diagnostics: jscissors, call by call](/deep-dive-jvm-diagnostics?id=_6-jscissors-what-the-code-does-call-by-call)
- 🌐 <a href="reports/jscissors.html" target="_blank" rel="noopener">A jscissors report</a> (another trace, the shipped sample: click around)
- 🧠 CLI reference: [playground debug jscissors](/playground%20debug%20jscissors), [playground analyze jscissors](/playground%20analyze%20jscissors)
- 🔗 Next step on a hang: [playground analyze thread-dump](/playground%20analyze%20thread-dump)

## 🅾️ Oracle XStream CDC lags or is idle

The Oracle XStream CDC source is `RUNNING`, but no change comes in, or it lags. The answer is on the database side, in the
`orclcdc_diag_<date>.html` report the customer generates with `orclcdc_diag.sql`: hundreds of tables, digested into findings.

<video src="videos/session-oracle-xstream-report.mp4" poster="images/sessions/oracle-xstream-report.png" controls playsinline width="100%"></video>

**In this session**

- prerequisites (ARCHIVELOG, supplemental logging, streams pool), capture, LogMiner, outbound server
- findings most severe first, each quoted from its section of the report, with the SQL to fix it
- root-cause patterns (undersized streams pool, flow control, aborted capture...)
- comparing two reports (`-f` twice), the symptom given with `-p`

**Commands**

```bash
playground analyze oracle-xstream-report -f orclcdc_diag_<date>.html -p "no change since 9:10"
playground analyze oracle-xstream-report -c oracle         # on the playground XStream example
playground analyze oracle-xstream-report --sample synthetic_failures --output-dir /tmp/xstream
```

**Links**

- 🌐 <a href="reports/oracle-xstream-report.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze oracle-xstream-report](/playground%20analyze%20oracle-xstream-report)

## ☸️ What is wrong in this CFK cluster?

A Confluent for Kubernetes cluster is broken and the customer sends a support bundle: pod logs, CR yamls, events and pod
states. The analyzer sorts it into issues by severity and component, with a timeline of the recent changes.

<video src="videos/session-cfk-bundle.mp4" poster="images/sessions/cfk-bundle.png" controls playsinline width="100%"></video>

**In this session**

- a folder, `.tar.gz` or `.zip` analyzed in a container, secrets / IPs / hostnames sanitized
- versions, recent changes, and issues by category: pod failures, OOMKilled, probes, TLS, authentication...
- the `Caused by:` chain of each finding, the kubectl commands to run next, the CFK docs
- focusing with `--component`, `--severity`, `--top`

**Commands**

```bash
playground analyze cfk-bundle --bundle support-bundle.tar.gz
playground analyze cfk-bundle --bundle support-bundle.tar.gz --component connect --severity high
playground analyze cfk-bundle --sample synthetic --output-dir /tmp/cfk-bundle
```

**Links**

- 🌐 <a href="reports/cfk-bundle.html" target="_blank" rel="noopener">The HTML report shown in the session</a> (the real report: click around)
- 🧠 CLI reference: [playground analyze cfk-bundle](/playground%20analyze%20cfk-bundle)

## 📨 Produce realistic test data

You need records like the customer's: give a schema, get random records that match it, with the schema registered for you,
on any environment (SASL, mTLS, Confluent Cloud).

<video src="videos/session-topic-produce.mp4" poster="images/sessions/topic-produce.png" controls playsinline width="100%"></video>

**In this session**

- random records from an Avro, JSON Schema or Protobuf schema, with a key and headers, read back with `topic consume`
- a schema derived from one JSON record (`--derive-value-schema-as`)
- datagen schemas, tombstones, big records (`--record-size`)
- a steady flow until ctrl-c (`--nb-messages -1 --throughput 20`): the progress every 10 seconds, and the exact number of records sent
- `--forced-value`, `--value-format raw`, `--validate`, subject name strategies, compression

**Commands**

```bash
playground topic produce -t leads --nb-messages 5 --key 'lead-%g' --headers 'source:web,version:2' < scripts/cli/predefined-schemas/avro/lead.avsc
echo '{"order_id": 1, "customer": "acme", "amount": 9.99, "paid": true}' | playground topic produce -t payments --nb-messages 3 --derive-value-schema-as AVRO
playground topic produce -t trades --nb-messages 3 < scripts/cli/predefined-schemas/datagen/stock_trades_schema.avro
playground topic produce -t leads --tombstone --key 'lead-1'
playground topic produce -t big --nb-messages 2 --record-size 1000000 < scripts/cli/predefined-schemas/avro/lead.avsc
playground topic produce -t ticks --nb-messages -1 --throughput 20 --value '{"tick": %g}'     # ctrl-c to stop
playground topic consume -t ticks --count
```

**Links**

- 🍪 Deep dive: [`topic produce` under the hood, hands-on lab and repro recipes](/deep-dive-topic-produce.md)
- 🧠 CLI reference: [playground topic produce](/playground%20topic%20produce) (an example for each flag)

## 📥 Read a topic

`playground topic consume` finds the format on its own (Avro, Protobuf, JSON Schema, plain) and reads from the beginning.
On a big topic the first 100 records are rarely the ones you want: show the last ones, the record a connector is stuck on,
what arrived during an incident, or the records as JSON for `jq`. And when an example checks that data flowed, records
that cannot be deserialized are caught.

<video src="videos/session-topic-consume.mp4" poster="images/sessions/topic-consume.png" controls playsinline width="100%"></video>

**In this session**

- `--last N`: the most recent records, sorted by timestamp across the partitions
- `--partition 1 --offset 42`: the record a connector is stuck on
- `--from-timestamp 20s` (or a date, an epoch, `10m`, `2h`): what arrived from that time
- `--json`: one object per record, only the records on stdout, piped to `jq`
- `--count` (with `--grep`): records, not offsets
- `--min-expected-messages`: 5 offsets, but 2 records that are not Avro, so the check fails and says why

**Commands**

```bash
playground topic consume -t orders --last 3
playground topic consume -t orders --partition 1 --offset 42 --max-messages 1
playground topic consume -t orders --from-timestamp 20s                          # or "2026-10-22 10:30", 1792660170522, 10m, 2h
playground topic consume -t orders --last 3 --json | jq -c '{key, partition, offset, quantity: .value.quantity}'
playground topic consume -t orders --count --grep order-7
playground topic consume -t payments --min-expected-messages 5
```

**Links**

- 🍪 Deep dive: [`topic consume` under the hood, hands-on lab and repro recipes](/deep-dive-topic-consume.md)
- 🧠 CLI reference: [playground topic consume](/playground%20topic%20consume) (an example for each flag)

## 🪛 A producer gets RecordTooLargeException

Nobody changed the producer, but somebody changed the topic. Build a topic like the customer's with `playground topic`,
apply the config that breaks the producer, find it in the overrides of the topic, and fix it. The same commands work on
every environment, local or Confluent Cloud.

<video src="videos/session-topic-administration.mp4" poster="images/sessions/topic-administration.png" controls playsinline width="100%"></video>

**In this session**

- `topic create` with the partitions and configs of the case (any `kafka-topics --create` argument is passed through),
  and why it fails on an existing topic
- `topic get-offsets`: earliest and latest offset per partition; the total counts offsets, not records
- `topic alter --add-config max.message.bytes=1000` on a live topic, seen in the `Configs:` overrides of `topic describe`
- a 5 KB record refused by the broker: `RecordTooLargeException`
- the fix with `topic alter --delete-config`, and the same record accepted
- `topic delete`: the `<topic>-value` subject goes with the topic, permanently

**Commands**

```bash
playground topic create -t orders --nb-partitions 3 --config retention.ms=600000
playground topic produce -t orders --nb-messages 10 --key 'k%g' --value '{"id": %g}'
playground topic get-offsets -t orders
playground topic alter -t orders --add-config max.message.bytes=1000
playground topic describe -t orders
playground topic produce -t orders --nb-messages 1 --record-size 5000 < scripts/cli/predefined-schemas/avro/lead.avsc   # RecordTooLargeException
playground topic alter -t orders --delete-config max.message.bytes
playground topic delete -t orders
```

**Links**

- 🍪 Deep dive: [topic administration: under the hood, hands-on lab and repro recipes](/deep-dive-topic-administration.md)
- 🧠 CLI reference: [playground topic create](/playground%20topic%20create), [playground topic alter](/playground%20topic%20alter),
  [playground topic describe](/playground%20topic%20describe), [playground topic get-offsets](/playground%20topic%20get-offsets),
  [playground topic delete](/playground%20topic%20delete)

## 🔰 Schema not found after a cleanup

The producer was refused a new schema version, somebody "cleaned up" the subject, and now the consumers fail with
`Error retrieving Avro schema for id 2`. Replay the story with `playground schema`: register a schema without producing,
a version refused by the compatibility rule and its real fix, then the difference between a soft delete, which keeps the
ids readable, and a permanent one, which loses them.

<video src="videos/session-schema.mp4" poster="images/sessions/schema.png" controls playsinline width="100%"></video>

**In this session**

- `schema register`: subject, version and id; the id is global and travels in every record
- `schema set-compatibility BACKWARD`, and a v2 refused with `40901 READER_FIELD_MISSING_DEFAULT_VALUE` (exit 1)
- the real fix: a default on the new field, accepted as version 2
- `ValueSchemaId:2` in `topic consume`: a consumer only needs the id, never the subject
- soft delete: the subject is hidden, `schema get --id 2` still resolves, re-registering gives the same id
- `--permanent`: `40403 Schema 2 not found`, what the consumers get; registering again gives a new id

**Commands**

```bash
playground schema register --subject orders-value < /tmp/order-v1.avsc
playground schema set-compatibility --subject orders-value --compatibility BACKWARD
playground schema register --subject orders-value < /tmp/order-v2-bad.avsc     # 40901, exit 1
playground schema register --subject orders-value < /tmp/order-v2.avsc         # the new field has a default
playground topic produce -t orders --nb-messages 2 < /tmp/order-v2.avsc
playground topic consume -t orders --min-expected-messages 2 --timeout 60
playground schema delete --subject orders-value                # soft delete
playground schema get --id 2                                   # still resolves
playground schema delete --subject orders-value --permanent
playground schema get --id 2                                   # 40403 Schema 2 not found
```

**Links**

- 🍪 Deep dive: [Schema Registry: under the hood, hands-on lab and repro recipes](/deep-dive-schema.md)
- 🧠 CLI reference: [playground schema register](/playground%20schema%20register),
  [playground schema set-compatibility](/playground%20schema%20set-compatibility),
  [playground schema get](/playground%20schema%20get), [playground schema delete](/playground%20schema%20delete)

## 📈 Is version Y slower? Benchmark two versions

Since the upgrade, the JDBC sink feels slower. `connector benchmark` measures it on the example you run: for each version it
switches the plugin, warms up, drains a backlog and records the workers, then compares the versions.

<video src="videos/session-benchmark.mp4" poster="images/sessions/benchmark.png" controls playsinline width="100%"></video>

**In this session**

- drain mode: pause, load `--nb-records`, resume, time the drain (no load script needed for a sink)
- two `--connector-tag`: the comparison of the versions, the original version restored at the end
- records/s, put batch time, running ratio, CPU, GC, and the flight recording of the measure
- lower bounds, benchmark history, sources and fully managed connectors

**Commands**

```bash
playground connector benchmark --nb-records 3000000 --connector-tag 10.8.4 --connector-tag 10.9.9 --output-dir /tmp/benchmark
playground connector benchmark --mode steady --duration 5m          # a throughput over a duration instead of a drain
```

**Links**

- 🍪 Deep dive: [`connector benchmark`: drain vs steady, loads, versions, hands-on lab](/deep-dive-connector-benchmark.md)
- 🌐 <a href="reports/benchmark.html" target="_blank" rel="noopener">A benchmark report</a> (JDBC PostgreSQL sink 10.8.4 vs 10.9.9: click around)
- 🧠 CLI reference: [playground connector benchmark](/playground%20connector%20benchmark), and
  [⏱️ Benchmark a connector](/reusables?id=⏱️-benchmark-a-connector) in the Reproduction toolkit

## 🐌 A slow or broken network, on purpose

The customer blames the network: timeouts, a connector that fails during the night, rebalances on a slow link. Make the
network slow, lossy or cut, on the example you run, without changing the example or restarting a container, and see what
the connector does, and whether it recovers when the network comes back.

<video src="videos/session-network-traffic.mp4" poster="images/sessions/network-traffic.png" controls playsinline width="100%"></video>

**In this session**

- `debug degrade-traffic`: latency, jitter, loss, corruption, duplicates or a bandwidth limit with `tc netem`, run from a
  netshoot container in the network namespace of the container (nothing installed, any image)
- `tc` only delays what a container **sends**: `--latency 200ms` on connect adds 200 ms to the round trip, degrade the
  other side too for 400 ms
- each container keeps its own degradation until it is stopped or replaced by a new `--action start`
- several effects in one call, scoped to one `--port`; `--action status` shows what is applied and measures the round trip
- `debug block-traffic`: an `iptables` DROP, like a firewall: no error comes back, the client waits for its own timeout
- the JDBC sink fails with `SocketTimeoutException: Connect timed out`, and stays `FAILED` once the network is back: it
  needs a restart

**Commands**

```bash
playground debug degrade-traffic -c connect --destination postgres --action status
playground debug degrade-traffic -c connect --destination postgres --latency 200ms --action start
playground debug degrade-traffic -c postgres --destination connect --latency 200ms --action start      # both ways
playground debug degrade-traffic -c postgres --action stop                                               # each container keeps its own
playground debug degrade-traffic -c connect --destination postgres --port 5432 --latency 100ms --jitter 50ms --loss 5% --action start
playground debug degrade-traffic -c connect --action stop

playground debug block-traffic -c connect --destination postgres --port 5432 --action start
playground connector wait --connector postgres-sink --state FAILED --max-wait 300
playground container logs -c connect --errors --since 5m
playground debug block-traffic -c connect --destination postgres --port 5432 --action stop              # same flags as start
playground connector restart --connector postgres-sink
```

Recorded on the example `connect/connect-jdbc-postgresql-sink/postgres-sink.sh`.

> [!TIP]
> Without `--destination`, `degrade-traffic` applies to all the traffic of the container: use it when the destination
> has IP addresses that change (Confluent Cloud, a SaaS API). A container restart removes both the degradation and the
> block. Each `block-traffic --action start` adds one `iptables` rule and each `--action stop` removes one: started twice,
> stop twice (the `iptables-save` printed at the end shows what is left).

**Links**

- 🍪 Deep dive: [`block-traffic` and `degrade-traffic` under the hood, hands-on lab and repro recipes](/deep-dive-network-traffic.md)
- 📖 [Blocking traffic](/reusables?id=🚫-blocking-traffic) and [Degrade traffic](/reusables?id=🐌-degrade-traffic---add-latency-packet-loss-or-corruption)
  in the Reproduction toolkit
- 🧠 CLI reference: [playground debug degrade-traffic](/playground%20debug%20degrade-traffic),
  [playground debug block-traffic](/playground%20debug%20block-traffic), [playground connector wait](/playground%20connector%20wait)

## 🚚 Move a self-managed connector to fully managed

A customer wants to move a self-managed connector to Confluent Cloud: what does its configuration become, and will the move
lose or replay data? Rehearse it with the [Connector Migration Utility](https://github.com/confluentinc/connect-migration-utility):
a local Connect worker connected to Confluent Cloud runs the self-managed connector, `discovery` writes its fully managed
configuration, `migrate` creates the fully managed connector from the offsets of the self-managed one.

<video src="videos/session-connect-migration.mp4" poster="images/sessions/connect-migration.png" controls playsinline width="100%"></video>

**In this session**

- the self-managed AWS CloudWatch Metrics sink, RUNNING on a local worker connected to Confluent Cloud
- `discovery`: the summary (what can move, what cannot and why) and the generated fully managed configuration
  (`AwsCloudWatchMetricsSinkConnector` becomes `CloudWatchMetricsSink`, the Avro converter becomes `input.data.format`,
  secrets redacted)
- the three migration modes, and `stop_create_latest_offset`: no loss, no duplicates
- `migrate`: the secrets passed again with `--sensitive-property`, the fully managed connector RUNNING, the self-managed one
  STOPPED

**Commands**

```bash
playground run -f ccloud/connect-migration-utility/cloudwatch-metrics-sink.sh   # the example (Confluent Cloud + AWS credentials)

playground connector connect-migration-utility discovery
playground connector connect-migration-utility migrate --migration-mode stop_create_latest_offset \
  --sensitive-property 'aws.access.key.id=$AWS_ACCESS_KEY_ID' --sensitive-property 'aws.secret.access.key=$AWS_SECRET_ACCESS_KEY'
# --no-open: do not open the generated configs in the editor, nor the connector in the browser (scripts, agents)
```

| `--migration-mode` | Starts from | Self-managed connector | Trade-off |
| --- | --- | --- | --- |
| `create` (default) | no offsets | keeps running | replays or skips data, depending on the connector |
| `create_latest_offset` | its latest offsets | keeps running | no downtime, some duplicates while both run |
| `stop_create_latest_offset` | its latest offsets | stopped first | no loss, no duplicates |

> [!WARNING]
> Pass the secrets with single quotes (`'aws.secret.access.key=$AWS_SECRET_ACCESS_KEY'`): `migrate` expands the variable
> itself, so the value does not show in your terminal or shell history. After `migrate`, the configurations in
> `connect-migration-utility-discovery-output/` hold the real secrets: delete that folder when you are done. The fully
> managed connector is billed: delete it with `playground connector delete` once the rehearsal is over.

**Links**

- 🍪 Deep dive: [fully managed connectors: what differs from self-managed, hands-on lab](/deep-dive-fully-managed.md)
- 📁 The example: [ccloud/connect-migration-utility](https://github.com/vdesabou/kafka-docker-playground/tree/master/ccloud/connect-migration-utility)
- 🧠 CLI reference: [playground connector connect-migration-utility discovery](/playground%20connector%20connect-migration-utility%20discovery),
  [playground connector connect-migration-utility migrate](/playground%20connector%20connect-migration-utility%20migrate)
- 📚 The utility, its modes and the supported connectors: [confluentinc/connect-migration-utility](https://github.com/confluentinc/connect-migration-utility)

## 🏗️ Deploy a fully managed connector with Terraform

The customer manages their fully managed connectors with Terraform: deploy the connector of a playground example the same
way, from the same JSON config, and see the HCL it becomes. Running it again updates the connector in place, and deleting it
runs `terraform destroy`.

<video src="videos/session-terraform.mp4" poster="images/sessions/terraform.png" controls playsinline width="100%"></video>

**In this session**

- `--terraform`: the JSON config of the Datagen example becomes HCL, then `terraform init`, `plan` and `apply`
- the secrets in `config_sensitive`, masked in the output
- the folder of the connector, with its `connector.tf` and its state
- a changed config, the same command: the plan shows `~ "max.interval" = "10000" -> "1000"`, the connector is updated in place
- `connector delete` runs `terraform destroy`

**Commands**

```bash
envsubst < /tmp/datagen.json | playground connector create-or-update -c DatagenSource_playground --terraform --wait
terraform -chdir=$(ls -d .terraform-playground/DatagenSource_playground-*) state list
sed -i '' 's/"10000"/"1000"/' /tmp/datagen.json
envsubst < /tmp/datagen.json | playground connector create-or-update -c DatagenSource_playground --terraform
playground topic consume -t datagen_pageviews --last 3
playground connector delete --connector DatagenSource_playground
```

Recorded on the example `ccloud/fm-datagen-source/fully-managed-datagen-source.sh`: its config in `/tmp/datagen.json`, with
`"$CLOUD_KEY"` / `"$CLOUD_SECRET"` placeholders replaced by `envsubst`.

**Links**

- 🍪 Deep dive: [fully managed connectors: what differs from self-managed, hands-on lab](/deep-dive-fully-managed.md)
- 📖 [Fully managed connectors with Terraform](/reusables?id=🏗️-fully-managed-connectors-with-terraform)
- 🧠 CLI reference: [playground connector create-or-update](/playground%20connector%20create-or-update),
  [playground connector delete](/playground%20connector%20delete)

## 👤 A fully managed connector with a service account loses an ACL

The examples run their fully managed connectors with an API key that can do anything on the cluster. The customer's
connector runs with a [service account](https://docs.confluent.io/cloud/current/connectors/service-account.html) and the
least ACLs, and fails with `Missing write permission on topic(s)`. Run the example the customer's way, remove the ACL they
lack, and let `connector diagnose` find it.

<video src="videos/session-ccloud-service-account.mp4" poster="images/sessions/ccloud-service-account.png" controls playsinline width="100%"></video>

**In this session**

- `PG_CCLOUD_SERVICE_ACCOUNT=true` (what `playground run --ccloud-service-account` sets): the connector gets its own
  service account, the ACLs of the documentation derived from its config, and the API key is removed from its config
- `rbac acl list --connector`: the ACLs of the service account of the connector
- the customer's case: `WRITE` on the topic deleted, the connector restarted, the task `FAILED`
- `connector diagnose`: the missing ACL, and the command that creates it again
- `connector delete` deletes the service account and its ACLs too

**Commands**

```bash
playground run -f ccloud/fm-datagen-source/fully-managed-datagen-source.sh --ccloud-service-account   # every connector of the example

playground rbac acl list   --connector DatagenSource_$USER
playground rbac acl delete --connector DatagenSource_$USER --operation WRITE --resource Topic:datagen_pageviews
playground connector restart --connector DatagenSource_$USER
playground connector wait --connector DatagenSource_$USER --state FAILED --max-wait 600
playground connector diagnose --connector DatagenSource_$USER
playground rbac acl create --connector DatagenSource_$USER --operation WRITE --resource Topic:datagen_pageviews
playground connector delete --connector DatagenSource_$USER
```

| Option of `playground run` | ACLs of the service account |
| --- | --- |
| `--ccloud-service-account` | the ACLs of the documentation, derived from the connector config |
| `--ccloud-service-account-acls full` | every operation on every topic, group and transactional id: to rule ACLs out |
| `--ccloud-service-account-acls none` | none: add them one by one with `playground rbac acl create --connector` |
| `--ccloud-service-account-id sa-xxxxx` | an existing service account (set up like the customer's), as is: no ACL created nor deleted |
| `PG_CCLOUD_SERVICE_ACCOUNT_ACL_EXCLUDE="READ Group:"` | the ACLs of the documentation, except the ones matching the regex |

> [!NOTE]
> An ACL change takes up to a minute to be applied in Confluent Cloud: wait a minute before restarting the connector. A
> restart is asynchronous: right after it, the status can still be `FAILED`, and `connector wait` stops on it, so retry
> the restart and the wait (the session does it in a loop). The
> principal that creates the connector needs the Assigner role on the service account: the playground grants it to the
> owner of `CONFLUENT_CLOUD_API_KEY`. Recorded on the example `ccloud/fm-datagen-source/fully-managed-datagen-source.sh`,
> its config in `/tmp/datagen-sa.json` with `"$CLOUD_KEY"` / `"$CLOUD_SECRET"` placeholders replaced by `envsubst`.

**Links**

- 📖 [Fully managed connectors with a service account](/reusables?id=👤-fully-managed-connectors-with-a-service-account)
  in the Reproduction toolkit
- 🍪 Deep dive: [fully managed connectors: what differs from self-managed, hands-on lab](/deep-dive-fully-managed.md)
- 🧠 CLI reference: [playground run](/playground%20run), [playground rbac acl](/playground%20rbac%20acl),
  [playground connector diagnose](/playground%20connector%20diagnose)
