---
name: kdp-repro-model
description: |
  Create, edit, run, verify, bisect, export or import a reproduction model of kafka-docker-playground (the private
  `reproduction-models/` submodule) — `playground repro bootstrap` (always, never a hand-written .sh; `--no-run`
  from an agent), building the scenario from a customer config, expected / actual / status header,
  `playground repro assert` verdicts, `repro bisect` across plugin versions, `repro diff`, `repro list`,
  `repro export` / `import` bundles, and the secret scan (`repro check`, pre-commit hook). Use when asked to
  reproduce a customer issue, to create / bootstrap / fix / share a repro model, or to find the version where a
  behaviour changed.
---

# Reproduction models

Mental model, every flag and the recipes: `docs/deep-dive-reproduction-models.md`.


```bash
playground repro bootstrap              # scaffold a new model in reproduction-models/
playground repro diff [-f <repro script>] [--summary]     # what it changes vs its base example: connector keys changed / added / removed + diffs
playground repro list [--mine] [--case <n>] [--status <text>] [--verdict reproduced|not-reproduced|none] [--grep <regex>] [--json]   # find models again
playground repro export [-f <repro script>] [--dry-run]   # self-contained bundle (+ repro-manifest.json, <model>.REPRO.md), committed or not, blocked if it holds a secret (--force)
playground repro export --all-uncommitted                 # every new or modified model
playground repro export --include-artifacts               # also pack connector zip/jar and files referenced by absolute path
playground repro export --report-only                     # the hand-off report (<model>.REPRO.md, also in every bundle) on stdout, for a Jira
playground repro import -f <bundle.tgz | https://…> [--dry-run | --run] [--on-conflict abort|rename|overwrite]
playground repro check [--staged | -f <repro script> | --all] [--json]   # same secret / customer data scan, before a commit
```

`repro bootstrap` / `repro import` point `core.hooksPath` of the `reproduction-models` repository to
`scripts/repro-git-hooks/`, whose `pre-commit` runs `playground repro check --staged --skip-secrets-store`: a
commit holding a secret is refused. Remove the finding (use `${VAR}`), don't bypass the hook
(`--no-verify`, `PLAYGROUND_REPRO_SCAN=skip`) unless it's a false positive.

**⚠️ Always scaffold a new repro model with `playground repro bootstrap` — never hand-write the `.sh`
file.** Bootstrap copies the base example, adds the standard header (date, author, description,
documentation links, `# 💬 comments:` block with the `🎯 expected` / `💥 actual` / `🎫 jira` / `🩹 status` fields), copies and renames the docker-compose override, links the
example's support files (`README.md`, `stop.sh`, `benchmark-load.bash`…) into the repro folder, appends the
CLI cheat-sheet + snippets after `exit 0`, and registers the model in the CLI state/metrics. A hand-written
file looks almost right but is missing all of that.

Non-interactive form (what to use when driving it from an agent):

```bash
playground repro bootstrap -f "${PWD}/connect/connect-http-sink/http_no_auth.sh" -d "unknown magic byte dlq" --no-run
```

- `-f` is the **absolute path** of the example to use as basis; passing it skips the whole fzf menu.
  Without `-f`, the command is fully interactive.
- `-d` is the description; it is kebab-cased into the filename
  (`<base>-repro-<description>.sh`) and into the compose override
  (`docker-compose.<environment>.repro-<description>.yml`). Start the description with the 6-digit case
  number when there is one (e.g. `-d "123456 dlq not working"`) — bootstrap detects it and links the case.
- **Always pass `--no-run`** from an agent: the command generates the files and returns in a few seconds,
  printing the `playground run -f …` line. Without it, bootstrap opens the generated file in the editor,
  then runs `playground run --force-interactive-repro`, which kills every container and stops the
  running environment (in a terminal it asks first when containers run; an agent has no terminal and is not asked).

Then edit the generated file to build the scenario, and run it with `playground run -f <generated file>`.

Keep them minimal and focused on one issue, fill in expected vs actual in the header (`--expected` / `--actual` at
bootstrap, or `playground repro status -f <model> --expected … --actual …`), set the outcome with
`playground repro status --set "fixed in <version>"` (`--jira CC-…`), end the scenario with its verdict
(`playground repro assert --reproduced-if-log "<error>"`, `--reproduced-if-connector-state FAILED`,
`--reproduced-if-records-less-than N --topic <t>`, `--reproduced-if-command …`: 🐞 / ✅ with the versions, exit 0 both;
then `playground repro bisect --from <version> --to <version>` finds the version where the verdict changes),
and never include customer-sensitive data.

