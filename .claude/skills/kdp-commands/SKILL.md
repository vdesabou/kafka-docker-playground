---
name: kdp-commands
description: |
  Pick the right `playground` command in kafka-docker-playground before investigating anything by hand —
  a connector that fails, is stuck, slow or lagging, logs or a customer bundle (CFK, orclcdc_diag, thread / heap
  dumps, GC logs, JFR, pcap), the dead letter queue, offsets and consumer groups, schemas and compatibility,
  brokers and transactions, connector plugin versions / changelogs / CVEs / dependencies / source code, customer
  configs (CFK, Strimzi, terraform, .properties), CI results, benchmarks — and before typing a raw `docker`,
  `curl` on a REST API or a `kafka-*` command in a script or a running environment. Use when asked "how do I…",
  "why does…", "is there a command for…", or whenever you are about to grep the repo, read raw logs or write a
  raw docker / curl / kafka-* call.
---

# Pick the right playground command

The CLI has ~300 commands. Most support questions have one that answers them in a single bounded,
non-interactive call. Missing it costs an hour of grepping and tens of thousands of log lines in context.

## 1. Ask the CLI

```bash
playground find-command "<question or symptom, in your words>"          # best 5, with usage + deep dive
playground find-command "<question>" --json --limit 3 | jq -r '.[].command'
```

It ranks the catalog `docs/which-command.md`, the "Recipes for support repros" table of every
`docs/deep-dive-*.md` and the help of every command. Then read `playground <command> --help` (flags, example
output) before running it.

## 2. Read the catalog when going further

`docs/which-command.md` (in the repository) is the full catalog:

- **🥇 Questions answered in one call**: question → command (with the useful flags) → what it replaces.
- **Good to know**: gotchas of these commands (which ones follow forever, where the HTML reports land, untrusted
  bundles, `--checkout-only` vs `--open`…). Read it before using `analyze`, `container logs`, `connector-plugin`.
- **🥈 Use the `playground` CLI, not raw `docker` / `curl` / `kafka-*`**: the raw command → `playground` mapping,
  and the few legitimate exceptions. Check it every time you write a script (example, repro model).

## 3. Read the deep dive of the command family

For a support case or a "why does X behave like this" question, the matching `docs/deep-dive-*.md` page has the
mental model, the gotchas and a **"Recipes for support repros"** table (customer symptom → commands). The
`🍪` link printed by `find-command` names it; `docs/deep-dives.md` lists them all.

## When you add a command

Add a row to the 🥇 table of `docs/which-command.md` (first column: the question as someone would type it), and
to the recipes table of its deep dive when it answers a customer symptom. That is what makes it findable by
`find-command`, by this skill and on the website.
