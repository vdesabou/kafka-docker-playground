---
name: kdp-pr-review
description: |
  Review a kafka-docker-playground pull request (number, branch or local diff) against the
  repo-specific rules that a generic code review misses: exact utils.sh source line,
  PLAYGROUND_ENVIRONMENT, playground CLI instead of raw docker/curl/kafka-*, exit 111 for
  unsupported combinations, no hand edits to generated files (scripts/cli/playground,
  docs/content.md…), bashly regeneration matching the source, CI matrix entry for new
  examples, credentials in both ci.yml env blocks, no secrets / playground.ini /
  reproduction-models, issue/PR conventions. Use when asked to review a PR or a diff of
  this repository, or before opening one.
---

# kafka-docker-playground PR review

Complements `/code-review` (generic bugs). This skill checks the **repo conventions** in `CLAUDE.md`.

## 1. Get the diff

```bash
gh pr view <n> --repo vdesabou/kafka-docker-playground --json number,title,body,labels,files,headRefName,baseRefName
gh pr diff <n> --repo vdesabou/kafka-docker-playground > /tmp/kdp-pr-<n>.diff
gh pr checks <n> --repo vdesabou/kafka-docker-playground
```

For a local change: `git diff origin/master...HEAD` (or the working tree diff).

## 2. Check

Report each failed check with `file:line`, the rule, and the fix. Skip checks that don't apply.

### Example scripts (`connect/`, `ccloud/`, `other/`, …)

| Rule | How to check |
| --- | --- |
| `source ${DIR}/../../scripts/utils.sh` exactly (the CLI injects code after it) | grep the new/changed `.sh` |
| `PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}`, never a hardcoded `--environment plaintext` in `connect/` | grep `start-environment` |
| `playground` CLI rather than raw `docker`, `docker compose`, `curl` on Connect/SR REST, `kafka-*` | grep `docker \|curl .*:8083\|curl .*:8081\|kafka-console\|kafka-topics`. Allowed exceptions: `docker inspect` / `docker image ls`, `curl` on the example's own test endpoint |
| unsupported version combination → `exit 111`, not `exit 1` | look at version guards |
| assertions with bounded waits, not only `sleep` | read the end of the script |
| `log`/`logwarn`/`logerror`, no bare `echo` for messages | grep |
| heredocs: unquoted `EOF` for connector configs (`$VAR`), quoted `'EOF'` for Avro schemas (`%g`, `$`) | read |
| fully managed: `bootstrap_ccloud_environment`, connector named `<TYPE>_$USER`, cleanup trap for external resources, no hardcoded secret | read |
| new script is executable (`new file mode 100755`) | diff header |
| `stop.sh` present for a new folder | file list |

### New example folder

- added to a 🚀 line of `test_list` in `.github/workflows/ci.yml` (otherwise CI never runs it)
- entry in `docs/content-template.md` ending with `:<folder>:`
- new credentials in **both** `env:` blocks of `ci.yml`, `vars.` for non-secret values, `secrets.` for
  secrets; the PR body tells the owner which ones to create
- `README.md` present

### CLI (`scripts/cli/`)

| Rule | How to check |
| --- | --- |
| `scripts/cli/playground` never edited by hand | it changes only together with `scripts/cli/src/**`; regenerate in a clean worktree (`./scripts/cli/playground bashly-reload`) and compare: no diff expected |
| generated diff contains only this change | hunks of `scripts/cli/playground` map to the changed commands |
| `playground.yaml` / `playground.json` regenerated when `bashly.yml` changed | file list |
| partial path mirrors the command tree | `scripts/cli/src/commands/<cmd>/<sub>.sh` |
| flags reuse YAML anchors (`*connector`, `*verbose`…) instead of redefining | read `bashly.yml` diff |
| `conflicts:` declared on **both** flags (bashly only checks flags already parsed) | read |
| no prompt (`read -p`) without a TTY check (scripts and AI agents run the CLI with no stdin) | grep `read -p` |
| output meant for parsing (`--json`, a path) has no `log` lines on stdout | read |
| works with BSD and GNU tools (`sed -i ''`, `\t` in sed, `date -v`) | grep |
| helpers placed right: `cli_function.sh` (CLI only) vs `utils_function.sh` (also examples), not `scripts/utils.sh` | read |

### Never committed

`reproduction-models` submodule pointer, `playground.ini`, `playground-run-history`, `.ccloud/`,
`secrets.properties`, `*.pem` / `*.key`, `docs/content.md` / `docs/badges.md` / `docs/cli.md` hand edits,
the CLI reference pages written by `update-docs` (`docs/playground *.md`, `docs/cli-pages.js`), and
anything with customer data.

### Issue / PR conventions

- title with an emoji prefix (`🐛` bug, `🧠` CLI, `🧹` cleanup, `👾` new FM example, `⭐` big feature),
  the commit title ends with ` #<issue>`, the PR body contains `Fixes #<issue>`
- labels `bug 🐛` / `enhancement ✨` (+ `cfk` / `podman`), never `new 🆕`, `CI failing 🔥`,
  `CI ignore ⏭️`; no milestone
- the PR body says what was verified and what was not

## 3. Report

A table, most important first: `severity (🔴 must fix / 🟠 should fix / 🟢 nit) | file:line | rule | fix`,
then a one-line verdict. When asked to post it, use `gh pr review <n> --comment --body-file …` only
after the user approves the text. Never approve or merge.
