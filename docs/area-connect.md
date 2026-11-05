# 🔗 Connect

For cases about **Kafka Connect** and **connectors**: self-managed (Confluent Platform, CFK) and fully managed (Confluent
Cloud), sinks and sources, converters and transforms, offsets and lag, the dead letter queue, plugin versions, and
customer configs to reproduce. 170+ self-managed and 100+ fully managed connector examples are listed in the
[👾 Content](/content.md) page.

## 🚀 5 commands to try

```bash
# a FileStream sink that sends its records to the DLQ while Schema Registry is down, then replays them: the whole tour
playground run -f "$PWD/other/reprocess-dlq-messages-with-sink-connector/replay-dlq-messages-with-playground.sh"

playground connector diagnose                              # status, digest of the ERROR records, lag and next steps, in one call
playground topic dlq inspect --connector filestream-sink   # failed records grouped by error, with the root cause and the original offsets
playground connector show-lag --connector filestream-sink  # consumer lag of a sink until it reaches 0
playground container logs -c connect --errors              # error digest of the worker logs (without --errors, logs follow and never return)
```

Every self-managed connector example: `playground find-example "<connector>" --category connect`; fully managed:
`--category ccloud`.

## ❓ Your question, the answer

| Question | Command or example |
| --- | --- |
| A connector or a task is `FAILED`, why? | `playground connector diagnose` (`--connector <name>`), `connector status`, `connector tasks`, `container logs -c connect --errors` |
| It is `RUNNING` but writes nothing | `playground connector diagnose`, then `topic dlq inspect` when `errors.tolerance=all` sends the records to the dead letter queue; once fixed, `topic dlq replay` (`--dry-run` first) |
| When did it fail, restart, rebalance? | `playground connector history` (`--since 1h`), `connector restart --only-failed` |
| A sink lags, its lag is stuck | `playground connector show-lag` (`--max-wait`), `connector offsets get`, `consumer-group describe --group connect-<connector>` |
| Where is a source in its data? Start over, skip records | `playground connector offsets get\|alter\|reset`, `connector create-or-update --offsets '<json>'` (fully managed) |
| Is the connector slow? Where does the task time go? | `playground connector metrics` (`--watch 10s`), `connector benchmark` (drain or steady mode, several `--connector-tag`), `debug thread-dump` + `analyze thread-dump` |
| The customer's connector config: CFK `Connector`, Strimzi `KafkaConnector`, Terraform, `.properties`, `expand=info` dump | `playground connector create-or-update` reads them as they are, `connector convert <file>` turns them into a heredoc for an example, `repro bootstrap --config <file>` builds a reproduction model from them |
| Is this config valid? What differs from the running one? | `playground connector validate`, `connector diff` |
| What does this transform chain do to a record? | `playground connector smt test` (with the customer's `transforms.*` and a record) |
| Which version fixed it? What changed between two versions? | `playground connector-plugin changelog --connector-plugin <owner>/<name> --from <version> --grep "<symptom>"`, `connector-plugin config-diff --from <a> --to <b>`, `repro bisect --from <a> --to <b>` |
| Run the customer's plugin version | `playground run -f <example> --connector-tag <version>` (`--connector-zip` / `--connector-jar` for a patched build) |
| What does the code do at the customer's version? | `playground connector-plugin sourcecode --connector-plugin <owner>/<name> --connector-tag <version>` (`--grep`, two `--connector-tag` for the diff), `connector-plugin config-key` for one property |
| Which jar, dependency, CVE? | `playground connector-plugin dependencies\|search-jar\|cve-scan` |
| A fully managed connector: which version runs, which config, which offsets? | `playground connector-plugin fm-versions --connector-plugin confluentinc/<TYPE>`, the fully managed examples `ccloud/fm-*` (`connector status\|offsets\|create-or-update` work the same on Confluent Cloud) |
| Move a self-managed connector to fully managed | `playground connector convert`, the session [🚚 Move a self-managed connector to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed) |
| More logs, without a restart | `playground debug log-level set -p <package> -l TRACE`, `debug log-level get` |
| Customer log bundle, thread dumps, heap dumps | `playground analyze logs -f <bundle>`, `analyze thread-dump\|heap-dump\|gc-logs\|flight-recorder` (on the customer's files too) |
| A connector database: CDC prerequisites, rows landed? | `playground db cdc-check` (archivelog, `wal_level`, binlog, CDC tables…), `db sql << 'EOF' … EOF`, `db wait-for-rows` |
| An HTTP sink: what did the endpoint receive? | `playground tools http-server requests\|set-response\|reset` with the `connect/connect-http-sink` examples |
| Oracle CDC (LogMiner, XStream) lags or is idle | `playground analyze oracle-xstream-report`, `connector oracle-cdc-xstream generate-report`, the [🅾️ Oracle CDC](/deep-dive-oracle-cdc.md) deep dive |
| The same connector under the customer's security | `--environment sasl-ssl\|2way-ssl\|kerberos\|rbac-sasl-plain\|…` on `playground run`, `--environment cfk` for Confluent for Kubernetes |
| Which CP version changed the worker? | `--tag` on any run, `playground cp-changelog --from <version> --component kafka --grep connect` (Kafka Connect is part of Apache Kafka), `repro bisect --tag <a> --tag <b>` |

## 🍪 Deep dives

- [🔌 Deploy a connector](/deep-dive-connector-create-or-update.md): create, update, wait, validate, diff
- [🩺 A connector doesn't work](/deep-dive-connector-troubleshooting.md): `connector diagnose` and the dead letter queue
- [🧭 Offsets and lag](/deep-dive-offsets-and-lag.md): sinks, sources, consumer groups
- [🔀 Test a transform chain on a record](/deep-dive-connector-smt-test.md)
- [🧑‍💻 Connector plugins](/deep-dive-connector-plugin.md): versions, release notes, config keys, source code, jars
- [📈 Benchmark a connector](/deep-dive-connector-benchmark.md)
- [🌤️ Fully managed connectors](/deep-dive-fully-managed.md), [🅾️ Oracle CDC](/deep-dive-oracle-cdc.md)
- [📜 Container logs](/deep-dive-container-logs.md), [🔊 Log levels](/deep-dive-log-levels.md), [🧵 JVM diagnostics](/deep-dive-jvm-diagnostics.md)
- [🕹️ Running examples and changing versions](/deep-dive-run-and-versions.md), [🔐 Secured environments](/deep-dive-secured-environments.md)

## 🎬 Bite size sessions

- [🩺 A sink is RUNNING but writes nothing](/sessions?id=🩺-a-sink-is-running-but-writes-nothing)
- [🔌 The sink fails right after it is deployed](/sessions?id=🔌-the-sink-fails-right-after-it-is-deployed)
- [⏪ The lag of a sink is stuck](/sessions?id=⏪-the-lag-of-a-sink-is-stuck)
- [🕵️ A connector failed: read the logs, live or from a customer bundle](/sessions?id=🕵️-a-connector-failed-read-the-logs-live-or-from-a-customer-bundle)
- [🔀 What does this transform chain do to a record?](/sessions?id=🔀-what-does-this-transform-chain-do-to-a-record)
- [🧑‍💻 The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version)
- [📈 Is version Y slower? Benchmark two versions](/sessions?id=📈-is-version-y-slower-benchmark-two-versions)
- [🚚 Move a self-managed connector to fully managed](/sessions?id=🚚-move-a-self-managed-connector-to-fully-managed)

## 🧪 A support case in 3 commands

"Our sink is `RUNNING` but nothing reaches the destination": `errors.tolerance=all` sends the records it can't convert to
the dead letter queue, here because Schema Registry was unreachable.

```bash
playground run -f "$PWD/other/reprocess-dlq-messages-with-sink-connector/replay-dlq-messages-with-playground.sh" --tag <customer CP version>

# why nothing is written: status, error digest, lag and next steps
playground connector diagnose --connector filestream-sink

# which records failed, with the root cause; then replay them once the cause is fixed
playground topic dlq inspect --connector filestream-sink && playground topic dlq replay --connector filestream-sink --dry-run
```

Then `playground topic dlq replay --connector filestream-sink` and `connector show-lag --connector filestream-sink` to
show the fix. Turn it into a reproduction model with `playground repro bootstrap` (see
[🛠 Reproduction models](/toolkit-reproduction-models.md)), and run it with the customer's plugin version with
`--connector-tag`.
