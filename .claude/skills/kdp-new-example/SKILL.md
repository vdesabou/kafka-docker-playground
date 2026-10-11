---
name: kdp-new-example
description: |
  Add a new example to kafka-docker-playground — a self-managed connector example
  (connect/connect-<name>/) or a fully managed Confluent Cloud connector example
  (ccloud/fm-<name>/) — following the repo conventions that reviewers otherwise catch
  by hand: copy the closest sibling, exact utils.sh source line, PLAYGROUND_ENVIRONMENT,
  version guards with exit 111, stop.sh, README, docs/content-template.md entry,
  credentials wired into both ci.yml env blocks, a 🚀 test_list matrix entry, cleanup of
  external resources, and one successful run. Use when asked to add / create / write a
  new example or a "👾 Add … Fully Managed Connector example" issue.
---

# Add a new example

An example is a standalone, minimal, automated test of one connector or feature. It is optimised for CI
and fast reproduction, not production hardening. The repo `CLAUDE.md` describes the general
architecture. This skill is the checklist for a **new** example.

## 1. Start from the closest sibling

```bash
playground find-example "<connector> <feature>" --json --limit 5 | jq -r '.[] | "\(.path)  \(.connector_classes | join(","))"'
```

Copy the closest example of the **same kind** (self-managed `connect/…` or fully managed
`ccloud/fm-…`), ideally from the same vendor or protocol, and adapt it. Never start from an empty file:
the boilerplate carries conventions that are easy to miss.

| Kind | Folder | Script name | Connector name |
| --- | --- | --- | --- |
| Self-managed | `connect/connect-<name>-<sink\|source>/` | `<name>-<sink\|source>.sh` (variants: `<name>-sink-<variant>.sh`) | `<name>-sink` |
| Fully managed | `ccloud/fm-<name>-<sink\|source>/` | `fully-managed-<name>-<sink\|source>.sh` | `<ConnectorType>_$USER` (e.g. `MarketoSink_$USER`) |

## 2. The script

Required skeleton (the `source` line must be **exactly** this one: `playground run` injects code after it):

```bash
#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/../../scripts/utils.sh
```

Self-managed:

- Version guard first when needed: `if ! version_gt $CONNECTOR_TAG "x.y.z"; then logwarn "…"; exit 111; fi`,
  or the `connect_cp_version_greater_than_8` pattern of the siblings. `exit 111` means "skipped", not
  failed.
- `PLAYGROUND_ENVIRONMENT=${PLAYGROUND_ENVIRONMENT:-"plaintext"}`, then `playground start-environment
  --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.yml"`.
  Never hardcode `plaintext`: CI re-runs `connect/` examples under `cfk`.
- `docker-compose.plaintext.yml` adds the external system (database, mock server…) and sets
  `CONNECT_PLUGIN_PATH: /usr/share/confluent-hub-components/<owner>-<plugin>` on `connect`, like the
  sibling does. The plugin is resolved from that path.

Fully managed:

- Credentials as environment variables with argument fallback and a clear `logerror` + `exit 1` when
  missing (see `ccloud/fm-marketo-sink/fully-managed-marketo-sink.sh`). Never hardcode a secret.
- `bootstrap_ccloud_environment` (with `"<cloud>" "<region>"` when the connector needs a specific one)
  instead of `start-environment`.
- External resources (buckets, tables, leads…) named with
  `playground-${USER}-${GITHUB_RUN_NUMBER}${TAG_BASE}-$RANDOM`-style unique names, deleted by a
  `cleanup_cloud_resources` function registered with `trap cleanup_cloud_resources EXIT`, inside
  `set +e`.
- Delete then create the connector (`playground connector delete … > /dev/null 2>&1` in `set +e`), and
  end with `check_if_continue` before `playground connector delete`.

Both:

- `playground` CLI only: `playground connector create-or-update` (heredoc, unquoted `EOF` for `$VAR`),
  `playground topic produce` (schema with quoted `<< 'EOF'`), `playground topic consume
  --min-expected-messages N --timeout 60`. No raw `docker`, `curl` on Connect/SR, or `kafka-*` (see the
  mapping table in `CLAUDE.md`).
- **Assert the result**: data landed in the target (sink), or records consumed (source), with a bounded
  wait loop (`MAX_WAIT`, `CUR_WAIT`, `logerror` + `exit 1` on timeout), not just `sleep`.
- `log` / `logwarn` / `logerror`, never bare `echo` for messages.
- `chmod +x` the script.

## 3. The other files

| File | Content |
| --- | --- |
| `stop.sh` | self-managed: `stop_all "$DIR"`; fully managed: `maybe_delete_ccloud_environment` (copy the sibling) |
| `README.md` | `# <Title> connector`, `## Objective` with the docs link, what the script does, `## How to run` with the env vars / arguments |
| `docs/content-template.md` | one line in the right section (`## 🔗 Connectors`, or `### 🤖 Fully-Managed Connectors`), alphabetical, ending with `:<folder>:` (the badge placeholder), with an icon from `images/icons/` (add a small png if none fits) |
| `.github/workflows/ci.yml` | the folder appended to a 🚀 line of the `test_list` matrix with similar runtime and needs. New credentials go into **both** `env:` blocks (`build` and `execute_one_test` jobs): `vars.X` for non-secret values, `secrets.X` for secrets |

Never edit `docs/content.md` / `docs/badges.md` (generated by `playground update-readme`).

The repo owner has to create new GitHub `vars` / `secrets` (`gh variable set`, `gh secret set`). Never
do it yourself: list the names and expected values in the PR description.

## 4. Run it once

```bash
playground status          # ask before running if an environment is up: run stops it
playground run -f "$PWD/<folder>/<script>.sh"
```

Fix it until it ends with `✅ RESULT: SUCCESS`. Also check `bash -n` on every script, and
`playground connector status` / `playground container logs -c connect --errors` while it runs. For
fully managed, check that the cleanup deleted the external resources.

## 5. Issue and PR

Follow "Contributing: issues and pull requests" in `CLAUDE.md`. Fully managed title:
`👾 Add <Connector name> Fully Managed Connector example`; self-managed:
`👾 Add <Connector name> connector example`. Ask before creating the issue and the PR. The PR body lists
what was run and its result, the CI matrix line, and any GitHub `vars`/`secrets` the owner must create.
