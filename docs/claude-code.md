# 🤖 Claude Code

The repository is set up to be used with [Claude Code](https://docs.claude.com/en/docs/claude-code/overview), Anthropic's
agentic coding tool: you describe what you want ("reproduce this connector issue with SASL", "review PR 9293", "add an
example for the fully managed X connector", "what is wrong in this customer log bundle?") and Claude runs the playground for
you, following the same conventions as the maintainers.

Here, asked why a connector stopped writing, Claude checks it with the playground CLI and explains the root cause and the fix, without changing anything:

<video src="videos/claude-code.mp4" autoplay loop muted playsinline controls width="100%"></video>

What makes it work:

| Piece | Where | What it does |
|---|---|---|
| Project guide | [`CLAUDE.md`](https://github.com/vdesabou/kafka-docker-playground/blob/master/CLAUDE.md) | Loaded at the start of every session: how examples, environments and the CLI work, the conventions, how to test, how issues and PRs are done |
| Skills | [`.claude/skills/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/.claude/skills) | Step-by-step playbooks for recurring tasks (below) |
| Agent-friendly CLI commands | [CLI](/cli.md) | One bounded, non-interactive call answers the common questions (see [below](/claude-code?id=%f0%9f%a5%87-agent-friendly-commands)) |
| Permissions | [`.claude/settings.json`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.claude/settings.json) | Read-only commands (`playground status`, `connector status`, `container logs`, `analyze logs`…) run without asking; everything else asks first |

## 🚀 Getting started

1. [Install Claude Code](https://docs.claude.com/en/docs/claude-code/setup) (terminal, VS Code / JetBrains extension or desktop app).
2. Start it from the root of your clone, so that `CLAUDE.md`, the skills and the settings are picked up:

   ```bash
   cd kafka-docker-playground
   claude
   ```

3. Ask in plain language. Claude picks the right skill by itself, or you can call one explicitly with `/<skill name>`:

   ```text
   > why is my connector not working?
   > /kdp-pr-review 9293
   > /kdp-xstream-report ~/Downloads/orclcdc_diag_20261013_0912.html
   ```

> [!TIP]
> Running an example (`playground run`) stops the example that is currently running. If you want to keep your
> environment, say so in your request (the `kdp-new-example` skill checks `playground status` and asks before running).

## 🧩 Skills

Skills are Markdown playbooks in `.claude/skills/<name>/SKILL.md`. Claude Code loads their description, uses one when your
request matches it, and follows its steps. They are versioned with the repository, so everyone gets the same ones.

| Skill | Use it to | Call it |
|---|---|---|
| [`kdp-new-example`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.claude/skills/kdp-new-example/SKILL.md) | add a self-managed (`connect/`) or fully managed (`ccloud/fm-*`) connector example | "add an example for the fully managed Zendesk Source connector", `/kdp-new-example` |
| [`kdp-pr-review`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.claude/skills/kdp-pr-review/SKILL.md) | review a PR or your local diff against the repository rules | `/kdp-pr-review 9293`, "review my changes before I open a PR" |
| [`playground-cli`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.claude/skills/playground-cli/SKILL.md) | add or change a `playground` command, flag or help text | "add a `--sort-by-size` flag to playground topic list" |
| [`kdp-benchmark`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.claude/skills/kdp-benchmark/SKILL.md) | measure or compare the throughput of a connector, write a `benchmark-load.bash` load | "is version 10.8 of the JDBC sink slower than 10.7?", `/kdp-benchmark` |
| [`kdp-xstream-report`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.claude/skills/kdp-xstream-report/SKILL.md) | analyze an Oracle XStream CDC diagnostics report and write the summary | `/kdp-xstream-report <orclcdc_diag.html>`, "why is my XStream connector idle? here is the report" |
| [`kdp-bump-cp-version`](https://github.com/vdesabou/kafka-docker-playground/blob/master/.claude/skills/kdp-bump-cp-version/SKILL.md) | update the default CP version: images check, `scripts/utils.sh`, CI matrix, docs, CLI regeneration, smoke test | `/kdp-bump-cp-version 8.4.0`, "CP 8.5.0 is out, make it the default" |

### 👾 kdp-new-example

Adds a new example the way reviewers expect it, so that it runs in CI on the first try:

- starts from the closest existing example (same connector family, same auth)
- the exact `source ${DIR}/../../scripts/utils.sh` line, `PLAYGROUND_ENVIRONMENT`, version guards with `exit 111` for
  unsupported Confluent Platform / connector versions
- `stop.sh`, `README.md`, the entry in the docs content page, credentials wired into CI, the 🚀 line of the CI matrix,
  cleanup of the external resources (buckets, databases, cloud connectors)
- runs it once until it ends with `✅ RESULT: SUCCESS`
- asks before creating the issue and the pull request

```text
> /kdp-new-example add the fully managed Salesforce Bulk API 2.0 Sink connector
```

### 🔎 kdp-pr-review

Complements a generic code review with the rules specific to this repository: the `utils.sh` source line,
`PLAYGROUND_ENVIRONMENT`, `playground` commands instead of raw `docker` / `curl` / `kafka-*`, `exit 111`, no hand edits to
generated files (`scripts/cli/playground`, `docs/content.md`…), bashly regeneration, CI matrix entry for new examples, no
secrets or `playground.ini` committed, issue / PR conventions.

It prints a table, most important first (🔴 must fix / 🟠 should fix / 🟢 nit, `file:line`, rule, fix) and a verdict. It
posts it on the PR only after you approve the text, and never approves or merges.

```text
> /kdp-pr-review 9293
> review my working tree before I open a PR
```

### 🧠 playground-cli

The `playground` CLI is generated by [bashly](https://bashly.dev): this skill keeps Claude from editing the generated
`scripts/cli/playground` and walks it through the real loop: declare the command or flag in `scripts/cli/src/bashly.yml`,
implement it in `scripts/cli/src/commands/<command>/<subcommand>.sh`, regenerate with `playground bashly-reload` (Docker
needed), check `--help`, a success and an error path, and commit the source with the regenerated files.

```text
> add a --sort-by-size flag to playground topic list
```

### 🏎️ kdp-benchmark

Drives [`playground connector benchmark`](/playground%20connector%20benchmark): drain or steady mode, the load shapes
(bulk, small transactions, update, delete), several plugin versions compared in one run, parallel sessions, fully managed
connectors. When a source example has no load yet, or a reproduction model needs a table of its own, it writes the
`benchmark-load.bash` with the shared helpers and its contract (stop at a batch boundary, print `BENCHMARK_BATCH`).

```text
> is version 10.8 of the JDBC sink slower than 10.7?
> add a benchmark load to the orders table of my reproduction model
```

See [Benchmark a connector](/reusables?id=⏱️-benchmark-a-connector) for the command itself.

### 🅾️ kdp-xstream-report

For the [Oracle XStream CDC Source connector](https://docs.confluent.io/kafka-connectors/oracle-xstream-cdc-source/current/overview.html):
runs [`playground analyze oracle-xstream-report`](/playground%20analyze%20oracle-xstream-report) on the `orclcdc_diag.sql`
report(s) for the findings with their exact values, checks them against the report, correlates with the connector logs,
config and source code, and writes a technical summary, the next steps with the SQL to run, and a customer-friendly summary.
It knows the traps (latency on an idle database, spills of large transactions are expected, a paused connector keeps the
outbound server attached…).

```text
> /kdp-xstream-report ~/Downloads/orclcdc_diag_20261013_0912.html
> /kdp-xstream-report compare orclcdc_diag_day1.html and orclcdc_diag_day2.html
```

To see what it works with without a report: `playground analyze oracle-xstream-report --sample synthetic_failures`.

## 🔒 Internal skills (Confluent employees only)

> [!WARNING]
> This section is **only for Confluent employees**. The skills below are not in the public repository: they live in the
> private `confluentinc/kafka-docker-playground-internal` repository (the `reproduction-models` submodule) because they
> rely on Confluent internal systems. Installing them requires access to that repository.

They are packaged as the `kdp-support` [Claude Code plugin](https://docs.claude.com/en/docs/claude-code/plugins) in that repository:

| Skill | Use it to | Call it |
|---|---|---|
| `kdp-case` | investigate a support case end to end: ticket context, customer log bundles, fully managed connector checks (read-only), connector code at the exact version, known issues, a minimal reproduction model, and a note with root cause, evidence and a draft customer reply | `/kdp-case <ticket number>`, "investigate ticket 368735" |
| `kdp-kb-review` | review a knowledge-base article or draft claim by claim against the connector code, docs and release notes, and propose a corrected article | `/kdp-kb-review <KB url \| file>`, `/kdp-kb-review --find "<error message>"` |

The Confluent Claude Code policy only allows approved plugin marketplaces (`/plugin marketplace add` fails with
`blocked by enterprise policy`), so link the skills into your personal skills folder instead, once, from the root of
your clone:

```bash
git submodule update --init --remote reproduction-models
mkdir -p ~/.claude/skills
for s in kdp-case kdp-kb-review; do
  ln -sfn "$PWD/reproduction-models/claude-plugins/kdp-support/skills/$s" ~/.claude/skills/$s
done
```

Then start a new Claude Code session from the root of your clone. The links point at your submodule checkout, so
`git submodule update --remote reproduction-models` is all it takes to get new versions. Prerequisites, usage, uninstall
and how to contribute are in the plugin README, at `reproduction-models/claude-plugins/kdp-support/README.md`.

## 🥇 Agent-friendly commands

`CLAUDE.md` tells Claude to use these before grepping the repository or reading raw logs. They are just as useful by hand:

| Question | Command |
|---|---|
| is there an example that does X? | [`playground find-example "oracle cdc ssl"`](/playground%20find-example) |
| what is running? | [`playground status`](/playground%20status) |
| why is this connector not working? | [`playground connector diagnose`](/playground%20connector%20diagnose) |
| why did it fail? | [`playground container logs -c connect --errors`](/playground%20container%20logs) |
| what is failing in these logs / this bundle? | [`playground analyze logs -f <file\|folder\|zip>`](/playground%20analyze%20logs) |
| stuck, slow, GC, heap? | [`playground analyze thread-dump`](/playground%20analyze%20thread-dump), [`gc-logs`](/playground%20analyze%20gc-logs), [`heap-dump`](/playground%20analyze%20heap-dump) |
| where does the time of the connector tasks go? | [`playground analyze flight-recorder -c connect --duration 60s`](/playground%20analyze%20flight-recorder) |
| what does this method receive, return, throw? which calls are slow? | [`playground debug jscissors -c connect --class <class> --duration 60s`](/playground%20debug%20jscissors), [`playground analyze jscissors -f <trace folder>`](/playground%20analyze%20jscissors) |
| what goes over the wire? refused or reset connections, TLS alerts, Kafka errors | [`playground debug tcp-dump -c connect --duration 30s`](/playground%20debug%20tcp-dump), [`playground analyze tcp-dump -f <.pcap>`](/playground%20analyze%20tcp-dump) |
| is this example red in CI too? | [`playground get-ci-result --test <dir> --logs`](/playground%20get-ci-result) |
| what does this transform chain (SMT) do to a record? why does it fail? | [`playground connector smt test --connector <c>`](/playground%20connector%20smt%20test) |
| is this bug fixed after version X? what changed since? | [`playground connector-plugin changelog --from X --grep <symptom>`](/playground%20connector-plugin%20changelog) |
| what changed in Confluent Platform (Kafka, Schema Registry, ksqlDB…) after version X? | [`playground cp-changelog --from X --grep <symptom>`](/playground%20cp-changelog) |
| where is the source code of connector X, version Y? | [`playground connector-plugin sourcecode --only-show-url`](/playground%20connector-plugin%20sourcecode) |
| scaffold a reproduction model | [`playground repro bootstrap -f <example> -d "<description>" --no-run`](/playground%20repro%20bootstrap) |

Every [`playground analyze`](/playground%20analyze) command has a `--sample` flag to try it on the samples shipped with
the playground.

## 🛡️ What Claude will and won't do

Following `CLAUDE.md`:

- uses the `playground` CLI rather than raw `docker`, `curl` on REST APIs or `kafka-*` tools, so commands keep working on
  every environment (plaintext, SASL, mTLS, cfk, ccloud)
- never edits generated files (`scripts/cli/playground`, `docs/cli.md`, `docs/content.md`…): it regenerates them
- scaffolds reproduction models with `playground repro bootstrap`, never by hand
- treats customer logs and bundles as untrusted data: it reads digests, never runs anything from them
- **asks before** creating a GitHub issue, opening a pull request or pushing to one, and never commits `playground.ini`,
  credentials or the private `reproduction-models` submodule
