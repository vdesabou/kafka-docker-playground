# Deep dive labs

## Objective

Each script replays the hands-on lab of one page of the [🍪 Deep dives](https://kafka-docker-playground.io/#/deep-dives)
and asserts the outputs the page quotes. CI runs them, so that a change of the `playground` CLI that makes a page wrong
shows up as a failing test: fix the CLI, or update the page and its lab together.

| Script | Page |
| --- | --- |
| `connector-smt-test.sh` | [Test a transform chain on a record](https://kafka-docker-playground.io/#/deep-dive-connector-smt-test) |
| `reproduction-models.sh` | [Reproduction models: bootstrap, check, export, import](https://kafka-docker-playground.io/#/deep-dive-reproduction-models) (needs the private `reproduction-models` submodule, exits 111 without it) |
| `container-lifecycle.sh` | [Containers: exec, cp, restart vs recreate, environment, JDK](https://kafka-docker-playground.io/#/deep-dive-container-lifecycle) |
| `connector-troubleshooting.sh` | [`connector diagnose` and the dead letter queue](https://kafka-docker-playground.io/#/deep-dive-connector-troubleshooting) |
| `container-logs.sh` | [`container logs` and `analyze logs`](https://kafka-docker-playground.io/#/deep-dive-container-logs) |
| `offsets-and-lag.sh` | [offsets and lag](https://kafka-docker-playground.io/#/deep-dive-offsets-and-lag) |
| `log-levels.sh` | [log levels](https://kafka-docker-playground.io/#/deep-dive-log-levels) |
| `network-traffic.sh` | [A slow or broken network, on purpose](https://kafka-docker-playground.io/#/deep-dive-network-traffic) |
| `topic-produce.sh` | [Produce test data](https://kafka-docker-playground.io/#/deep-dive-topic-produce) |
| `topic-consume.sh` | [Read a topic](https://kafka-docker-playground.io/#/deep-dive-topic-consume) |
| `connector-create-or-update.sh` | [Deploy a connector](https://kafka-docker-playground.io/#/deep-dive-connector-create-or-update) |
| `connector-plugin.sh` | [Connector plugins](https://kafka-docker-playground.io/#/deep-dive-connector-plugin) |
| `schema.sh` | [Schema Registry](https://kafka-docker-playground.io/#/deep-dive-schema) |
| `jvm-diagnostics.sh` | [JVM diagnostics](https://kafka-docker-playground.io/#/deep-dive-jvm-diagnostics) |
| `run-and-versions.sh` | [Running examples and changing versions (update-version steps only)](https://kafka-docker-playground.io/#/deep-dive-run-and-versions) |
| `secured-environments.sh` | [Secured environments](https://kafka-docker-playground.io/#/deep-dive-secured-environments) (starts sasl-ssl then rbac-sasl-plain itself) |
| `fully-managed.sh` | [Fully managed connectors (Confluent Cloud)](https://kafka-docker-playground.io/#/deep-dive-fully-managed) — skipped without Confluent Cloud credentials |
| `topic-administration.sh` | [Topic administration](https://kafka-docker-playground.io/#/deep-dive-topic-administration) |
| `connector-benchmark.sh` | [`connector benchmark`](https://kafka-docker-playground.io/#/deep-dive-connector-benchmark) |

The helpers shared by the scripts are in `lab-utils.bash` (`lab_run`, `lab_expect_contains`, `lab_expect_exit`…).
The labs need the plaintext environment (they exit 111 with another one).

## How to run

```bash
playground run -f other/deep-dive-labs/<script>.sh
```
