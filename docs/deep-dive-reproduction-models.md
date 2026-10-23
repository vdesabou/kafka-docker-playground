# 🍪 Deep dive: reproduction models (`playground repro`)

A reproduction model is an example rewritten to show **one** problem, so that anyone can reproduce it with a single
`playground run`. Four commands cover its life: `repro bootstrap` scaffolds it from an existing example, `repro check`
scans it for secrets and customer data before a commit, `repro export` packs it as a self-contained bundle for a
colleague, and `repro import` unpacks one. Takes about 15 minutes to read and run.

> [!TIP]
> The [🛠 Bootstrap reproduction model](/reusables?id=🛠-bootstrap-reproduction-model) and
> [📦 Share a reproduction model](/reusables?id=📦-share-a-reproduction-model) sections of the Reproduction toolkit show
> the commands, with a video of the interactive bootstrap. This page goes further: what each command generates or
> checks under the hood, the gotchas, a hands-on lab and recipes for support cases.

| You want | Command |
| --- | --- |
| a new model from an example, with menus | `playground repro bootstrap` |
| the same, without menus (scripts, AI agents) | `playground repro bootstrap -f "<absolute path of the example>" -d "<case number> <symptom>" --no-run` |
| to know whether a model holds a secret | `playground repro check -f <model>` (`--json`) |
| what a commit would push | `playground repro check --staged` (what the pre-commit hook runs) |
| to send a model to a colleague | `playground repro export -f <model>` (`--dry-run` first, `--include-artifacts`) |
| every model you changed, in one bundle | `playground repro export --all-uncommitted` |
| to run a model someone sent you | `playground repro import -f <bundle.tgz>` (`--dry-run`, `--on-conflict rename`) |

---

## 1. Mental model (the 3 things to remember)

1. **A model is a copy of an example, plus conventions that tools rely on.** `bootstrap` copies the example script to
   `reproduction-models/<folder>-<example folder>/<script>-repro-<description>.sh` and adds what a hand-written copy
   would miss:
   - a header (`🗓️ date`, `👤 author`, `💡 description`, `🔮 ticket` link when the description starts with 6 digits,
     `🔗 github file url`, `🌐 documentation`, and an empty `💬 comments:` block for expected vs actual),
   - its own copy of the docker compose override, renamed `<override>.repro-<description>.yml`, and the script pointed
     to it,
   - symlinks to the example's support files (`README.md`, `stop.sh`, `config-*`, `benchmark-load.bash`…), so they
     follow the public example,
   - a CLI cheat sheet in comments and `exit 0` at the end, then a snippets area below it.

   `export` reads that header (case number, author, base example), `check` treats the symlinks as public files, and
   `create-or-update` recognizes the path (see 3).

2. **Secrets are caught at three moments, with the same scan.** `repro check` (by hand), the pre-commit hook of
   `reproduction-models` (`repro check --staged`, set up by `bootstrap` and `import`), and `repro export`. The scan
   **blocks** on the value of a credential known to this machine (the `playground secrets` store, exported credential
   variables, `CLUSTER_CREDS` / `SCHEMA_REGISTRY_CREDS` of `playground.ini`, `~/.aws/credentials`) and on well-known
   token formats (AWS access key id, private key, GitHub / Slack token, Google API key, JWT, Azure storage account key).
   It only **warns** on possible customer data: email addresses (except `example.com`, `confluent.io`…), public IP
   addresses, hard-coded passwords that don't come from the base example. Values are never printed, only the file,
   the line and the kind.

3. **A model runs like an example, but more forgiving.** `playground run -f <model>` works the same, except that
   `connector create-or-update` doesn't stop the script when the connector isn't RUNNING: it warns and goes on
   (models often create a failing connector on purpose). Use `--wait` in a model that must stop there. The mode comes
   from the path of the last `playground run` (`*/reproduction-models/*`).

---

## 2. `repro bootstrap`: scaffolding

```bash
# with menus: pick the example, type the description, add options (custom SMT, plugin, pipeline), then it runs
playground repro bootstrap

# without menus: generate the files and return
playground repro bootstrap -f "${PWD}/connect/connect-http-sink/http_no_auth.sh" -d "123456 dlq not working" --no-run

# extras
playground repro bootstrap -f "…/jdbc-mysql-sink.sh" -d "123456 smt drops field" --custom-smt --no-run    # a no-op SMT to edit, built and wired in
playground repro bootstrap -f "…/debezium-mysql-source.sh" -d "123456 cdc to s3" --pipeline "…/s3-sink.sh" --no-run
playground repro bootstrap -f "…/http_no_auth.sh" -d "123456 two plugins" --connector-plugin confluentinc/kafka-connect-jdbc --no-run
```

What the description becomes: spaces → `-`, lower case, only letters, digits and `-` kept.
`-d "123456 DLQ not working!"` → `http_no_auth-repro-123456-dlq-not-working.sh` and
`docker-compose.plaintext.repro-123456-dlq-not-working.yml`.

| | `--no-run` | without (`-f` or menus) |
| --- | --- | --- |
| files generated, `playground run -f …` printed (and copied to the clipboard on macOS) | ✅ | ✅ |
| pre-commit hook set up, model counted in the CLI metrics | ✅ | ✅ |
| current model (`run.test_file`) set to the new one | ❌ the running example stays current | ✅ |
| opened in your editor | ❌ | ✅ |
| `playground run --force-interactive-repro` | ❌ | ✅: **kills every container** and starts the model |

Gotchas:

- **`-f` must be an absolute path.** A relative path fails (`do not use relative path for test file!`).
- **Always pass `--no-run` from a script or an agent**: without it, bootstrap opens an editor, then stops the running
  environment to run the new model.
- The description is required (`-d`); with `-f` and no `-d`, a prompt asks for it.
- The model folder is shared by every model of the same example: the symlinks (`README.md`, `stop.sh`…) are
  re-created, never duplicated. Delete a model by deleting its `.sh` and its compose override only.
- A name containing `perf` also enables Grafana (or SQL datagen for Debezium sources) on the first run.
- The ticket link is written for any description starting with 6 digits: `000000 test` gets a ticket link too.

---

## 3. `repro check` and the pre-commit hook

```bash
playground repro check                    # new and modified files of reproduction-models (git status)
playground repro check -f <model>         # the files export would pack for this model
playground repro check --staged           # the staged content, what the pre-commit hook checks
playground repro check --all --json       # one-time audit of every file
```

What a finding looks like, and the exit code:

| Level | Examples | Exit code |
| --- | --- | --- |
| 🔥 block | `contains the value of <credential name>`, `looks like an AWS access key id`, a credential file staged (`keyfile.json`, `*.pem`, `*.key`, `*.p12`, `*.jks`, `secrets.properties`, `playground.ini`) | 1 |
| 👀 warn | `email address at @<domain>`, `public IP address <ip>`, a hard-coded password, a dump / log / archive committed (`*.hprof`, `*.jfr`, `*.log`, `*.zip`…) | 0 |

`--json` prints `{files, blocks: [{location, message}], warnings: [{location, message}]}` (exit code 1 still means a
block).

Gotchas:

- **The hook only exists when `bootstrap` or `import` set it up** (`git config core.hooksPath
  <playground>/scripts/repro-git-hooks` in `reproduction-models`). An existing pre-commit hook or `core.hooksPath` is
  never replaced: you get a warning telling you to add `playground repro check --staged` to yours.
- The hook skips the `playground secrets` store (`--skip-secrets-store`) because reading it can prompt (1Password).
  `PLAYGROUND_REPRO_SCAN=full git commit` reads it too.
- **False positive** (a test JWT, a fake key from a vendor doc): `git commit --no-verify` or
  `PLAYGROUND_REPRO_SCAN=skip git commit`, and `repro export --force`. Real secret: replace the value with `${VAR}`
  (the variable comes from `playground secrets` or the environment).
- A value that is also in the public base example (a demo password like `confluent`) is not a finding.
- **A scan takes about 10 s** when it reads the credentials of the `playground secrets` store (`🔐 reading the 64
  credentials known to this machine … (op backend)`): that's the 1Password lookup, not the files.
- Version numbers (`7.7.12.1`) and private IP ranges (`10.`, `172.16-31.`, `192.168.`) are not reported as IP
  addresses.
- Symlinks to the public examples are never scanned: they're public files.

---

## 4. `repro export` and `repro import`: sharing

```bash
playground repro export -f <model> --dry-run          # what goes in, what the scan finds, nothing written
playground repro export -f <model> --output /tmp      # /tmp/playground_repro_<model name>_<date>.tgz
playground repro export --all-uncommitted             # playground_repro_all-uncommitted_<date>.tgz
playground repro export -f <model> --include-artifacts

playground repro import -f bundle.tgz --dry-run       # manifest, files, conflicts
playground repro import -f bundle.tgz --on-conflict rename
```

What goes in a bundle:

| Included | Left out |
| --- | --- |
| the script, its support files (`README.md`, `stop.sh`, `config-*`, `benchmark-load.bash`, `.gitignore`), and every entry of its folder whose **name appears** in the script or in a compose file it mentions | git-ignored files, `target/`, dumps (`*.hprof`, `*.jfr`), logs, archives, credential files, files over 50 MB |
| symlinks, **stored as their content** (the bundle doesn't depend on the version of the public example) | files outside the repository (connector zip, `~/Downloads/config.json`): listed only, packed under `<folder>/artifacts/` with `--include-artifacts` |
| `repro-manifest.json`: per model the last `playground run` line (from `playground-run-history`, without `--cluster-creds`), case number, author, base example, credential **names**, external files; the playground commit; the sha256 of every file | credential values |

What import does:

1. Extracts to a temporary folder and refuses absolute paths, `..`, special files, and files whose sha256 doesn't
   match the manifest.
2. Compares with your files: identical → skipped, new → written, different → **conflict**. `--on-conflict abort`
   (default) imports nothing and lists them, `rename` writes `<name>-imported-<YYYYMMDD>.<ext>` and updates the
   references in the imported script, `overwrite` replaces yours.
3. Restores the symlinks to public examples when your public file is identical, and rewrites the paths of the
   exporter's checkout (artifacts, `--custom-smt` jars) to yours.
4. Sets up the pre-commit hook, **makes the first model the current one**, and prints its `playground run` line, the
   missing credentials (`playground secrets set <NAME>`) and the external files you don't have.

Gotchas:

- **The run line comes from your history**: a model you never ran has none
  (`no 'playground run' found in playground-run-history`), and the importer won't know which `--tag` /
  `--connector-tag` to use. Run it once before exporting.
- The name test is a substring match: a file named `a.json` is packed when the script mentions `data.json`. Check the
  `--dry-run` list.
- On macOS the bundle is copied to the clipboard as a file: paste it in Slack to attach it (`--no-clipboard`).
- Export only works on models of `reproduction-models/` (the default `OUTPUT_FOLDER`).
- Import from a newer playground: `commit … is not in your checkout` means the model may use flags you don't have yet:
  `git pull`.

---

## 5. Hands-on lab (≈10 min, no container needed)

The lab writes into the private `reproduction-models` submodule: the last step deletes exactly what it created.

**Step 1: bootstrap without running**

```bash
playground repro bootstrap -f "${PWD}/connect/connect-filestream-sink/filestream-sink.sh" -d "000000 deep dive lab" --no-run
# (on macOS the run line goes to the clipboard: playground config set clipboard false to avoid it)
# 📂 Output folder is reproduction-models (set with OUTPUT_FOLDER environment variable)
# ✨ Creating file …/reproduction-models/connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh
# ✨ Creating file …/reproduction-models/connect-connect-filestream-sink/docker-compose.plaintext.repro-000000-deep-dive-lab.yml
# 🌟 command to run generated example
# playground run -f …/reproduction-models/connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh
# 👷 Number of repro models created so far: 25
# 🛠️ Number of repro models available: 1893
# 🛑 --no-run is set, not running the reproduction model
playground state get run.test_file      # unchanged: still the example that was running
```

**Step 2: what was generated**

```bash
m=reproduction-models/connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh
head -16 "$m"
# # 💡 description: 000000 deep dive lab
# # 🔮 ticket: https://confluent.zendesk.com/agent/tickets/000000        <- any 6 leading digits
# # 💬 comments:
grep -n "docker-compose" "$m"
# 21:playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000000-deep-dive-lab.yml"
grep -n "^exit 0" "$m"               # 110:exit 0 — the cheat sheet is above it, the snippets area below
ls -l reproduction-models/connect-connect-filestream-sink/README.md reproduction-models/connect-connect-filestream-sink/stop.sh
# README.md -> ../../connect/connect-filestream-sink/README.md
# stop.sh -> ../../connect/connect-filestream-sink/stop.sh
```

**Step 3: check it, with and without a secret**

```bash
playground repro check -f "$PWD/$m"
# 🕵️ scanning 3 file(s) of reproduction models for secrets and customer data
# 🔐 reading the 64 credentials known to this machine to look for their values (op backend)      <- ~10 s
# ✅ no secret nor customer data found
echo '# aws_access_key_id = AKIAABCDEFGHIJKLMNOP' >> "$m"          # a fake key, in the AWS format
playground repro check -f "$PWD/$m"; echo "exit=$?"
# 🔥    🔐 connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh:118 looks like an AWS access key id
# 🔥 ❌ 1 secret finding(s): remove them (use ${VAR} instead of the value)
# exit=1
playground repro check -f "$PWD/$m" --json | jq -c '.'
# {"files":3,"blocks":[{"location":"connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh:118","message":"looks like an AWS access key id"}],"warnings":[]}
sed -i '' '/AKIAABCDEFGHIJKLMNOP/d' "$m"                           # remove it (GNU sed: sed -i)
```

**Step 4: export**

```bash
playground repro export -f "$PWD/$m" --dry-run
# 🤷 …: no 'playground run' found in playground-run-history, the bundle will not say which flags to use
# 👷‍♂️ 1 reproduction model(s), 7 file(s):
#    🔖 connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh
#       ▶️  playground run -f {repro_dir}/filestream-sink-repro-000000-deep-dive-lab.sh
#    📄 connect-connect-filestream-sink/.gitignore
#    📄 connect-connect-filestream-sink/config-org.apache.kafka.connect.file.FileStreamSinkConnector.json  (symlink to …, stored as content)
#    📄 connect-connect-filestream-sink/README.md  (symlink to connect/connect-filestream-sink/README.md, stored as content)
#    …
# ✅ no secret nor customer data found
# 🔍 dry run: no bundle written
playground repro export -f "$PWD/$m" --output /tmp/deep-dive-repro --no-clipboard
# 📤 Exported bundle is available: /tmp/deep-dive-repro/playground_repro_filestream-sink-repro-000000-deep-dive-lab_2026-10-23.tgz (8.0K)
# 📥 To import it: playground repro import -f <path>/playground_repro_filestream-sink-repro-000000-deep-dive-lab_2026-10-23.tgz
tar tzf /tmp/deep-dive-repro/playground_repro_*.tgz
# repro-manifest.json and the 7 files under connect-connect-filestream-sink/
tar xzOf /tmp/deep-dive-repro/playground_repro_*.tgz repro-manifest.json | jq -c '.models[0] | {script, case, base_example, run_command}'
# {"script":"connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh","case":"000000","base_example":"connect/connect-filestream-sink","run_command":"playground run -f {repro_dir}/filestream-sink-repro-000000-deep-dive-lab.sh"}
```

**Step 5: import, with a conflict**

```bash
playground repro import -f /tmp/deep-dive-repro/playground_repro_*.tgz --dry-run
# 📦 bundle exported on 2026-10-23T11:14:12Z by vsaboulin from playground commit cf90238a7
# 🔖 …lab.sh   💡 000000 deep dive lab   🔮 https://confluent.zendesk.com/agent/tickets/000000   🧬 based on connect/connect-filestream-sink
# 📋 0 new, 7 identical, 0 conflicting file(s)                     <- it's your own model
# 🔍 dry run: nothing imported
echo "# a local change" >> "$m"
playground repro import -f /tmp/deep-dive-repro/playground_repro_*.tgz; echo "exit=$?"
#    ⚔️  conflict   connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh
# ❌ 1 file(s) differ from your copy, nothing imported. Use --on-conflict rename (keeps yours) or --on-conflict overwrite
# exit=1
playground repro import -f /tmp/deep-dive-repro/playground_repro_*.tgz --on-conflict rename
# ✏️  …/filestream-sink-repro-000000-deep-dive-lab.sh imported as …/filestream-sink-repro-000000-deep-dive-lab-imported-20261023.sh
# 📥 …tgz imported in …/reproduction-models
# ▶️  playground run -f …-imported-20261023.sh                       <- now the current model (run.test_file)
diff "$m" reproduction-models/connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-imported-$(date +%Y%m%d).sh
# the github file url line of the header now names the -imported- file (and your "# a local change" is not in it)
```

**Step 6: clean up**

```bash
d=reproduction-models/connect-connect-filestream-sink
rm -f "$d/filestream-sink-repro-000000-deep-dive-lab.sh" \
      "$d/filestream-sink-repro-000000-deep-dive-lab-imported-$(date +%Y%m%d).sh" \
      "$d/docker-compose.plaintext.repro-000000-deep-dive-lab.yml"
rm -rf /tmp/deep-dive-repro
git -C reproduction-models status --short connect-connect-filestream-sink   # same as before the lab
```

Don't delete the symlinks of the folder: other models of the same example use them. The import made the lab model the
current one: run an example (or `playground state set run.test_file <script>`) before relying on `playground re-run`.

---

## 6. Recipes for support repros

| Situation | Command |
| --- | --- |
| a new case | `playground find-example "<connector> <feature>"`, then `repro bootstrap -f <best hit> -d "<case> <symptom>" --no-run`; also look for an earlier model of the same symptom in `reproduction-models/` |
| the customer gave a connector config | paste it in the model, then `playground connector diff --connector <c> --file customer.json` (see the [`create-or-update` deep dive](/deep-dive-connector-create-or-update.md)) |
| the model must fail when the bug is fixed | assert at the end: `playground topic consume --min-expected-messages N --grep …`, or `connector create-or-update --wait` (see the [`topic consume` deep dive](/deep-dive-topic-consume.md)) |
| hand it to engineering / a colleague | run it once (for the run line), `repro export --dry-run`, then `repro export` (`--include-artifacts` for a custom jar) and attach the bundle |
| a colleague sent you a bundle | `repro import --dry-run`, then `repro import`, then the printed `playground run` line |
| test the fix on another version | `playground run -f <model> --connector-tag <fixed version>`, or `playground update-version` on the running model |
| a secret slipped in | replace it with `${VAR}` and `playground secrets set VAR …`; `repro check -f <model>` until it's clean |
| the commit is refused for a fake token | check the line it points to, then `git commit --no-verify` (only if it's not a real secret) |

Keep a model about one issue, write expected vs actual in `# 💬 comments:`, use neutral names (topics, tables,
hosts) and never customer data.

---

## 7. Cheat sheet

```bash
playground repro bootstrap [-f "<absolute path of the example>" -d "<case> <symptom>" --no-run] \
  [--custom-smt] [--connector-plugin <owner/name>] [--pipeline "<sink example>"]
playground repro check [-f <model> | --staged | --all] [--json] [--skip-secrets-store]
playground repro export [-f <model> … | --all-uncommitted] [--output <dir>] [--dry-run] [--include-artifacts] [--force] [--no-clipboard]
playground repro import -f <bundle.tgz> [--dry-run] [--on-conflict abort|rename|overwrite]
```

- Bootstrap = copy + header + own compose override + symlinks + cheat sheet. Scripts and agents: always `-f -d --no-run`.
- `<script>-repro-<kebab description>.sh`; 6 leading digits = ticket link.
- Secrets: blocked by `check`, the pre-commit hook and `export`. Customer data: warned only.
- Bundle = files + symlinks as content + manifest (run line, credential names, sha256). Run the model once first.
- Import: identical skipped, conflicts abort unless `rename` / `overwrite`, first model becomes current.
- In a model, `create-or-update` warns instead of failing: `--wait` to make it strict.
- Sources: [`repro/bootstrap.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/bootstrap.sh),
  [`repro/check.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/check.sh),
  [`repro/export.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/export.sh),
  [`repro/import.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/import.sh),
  [`scripts/repro-git-hooks/pre-commit`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/repro-git-hooks/pre-commit),
  helpers `repro_bundle_files` / `repro_bundle_scan` / `repro_install_git_hook` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 📖 [Bootstrap reproduction model](/reusables?id=🛠-bootstrap-reproduction-model) and
  [Share a reproduction model](/reusables?id=📦-share-a-reproduction-model) in the Reproduction toolkit
- 🍪 Deep dives: [`connector create-or-update`](/deep-dive-connector-create-or-update.md) (the warn-only wait of models),
  [`topic produce`](/deep-dive-topic-produce.md) and [`topic consume`](/deep-dive-topic-consume.md) (data in, assertions out)
- 🧠 CLI reference: [playground repro bootstrap](/playground%20repro%20bootstrap), [playground repro check](/playground%20repro%20check),
  [playground repro export](/playground%20repro%20export), [playground repro import](/playground%20repro%20import)
