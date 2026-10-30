# 🍪 Deep dive: reproduction models (`playground repro`)

A reproduction model is an example rewritten to show **one** problem, so that anyone can reproduce it with a single
`playground run`. Seven commands cover its life: `repro bootstrap` scaffolds it from an existing example, `repro assert`
ends it with its verdict, `repro bisect` runs it on several versions, `repro status` records what it proves and what came out of it, `repro check` scans it for secrets and customer data before a commit,
`repro export` packs it as a self-contained bundle for a colleague, and `repro import` unpacks one. Takes about 15 minutes to read and run.

> [!TIP]
> 🎬 Short on time? The video session [🧪 The life of a reproduction model](/sessions?id=🧪-the-life-of-a-reproduction-model) shows it in 4 minutes: `repro bootstrap --no-run`, a scenario edited and run, `repro check` catching a key, then `export` and `import` on another machine.
>
> The [🛠 Bootstrap reproduction model](/reusables?id=🛠-bootstrap-reproduction-model) and
> [📦 Share a reproduction model](/reusables?id=📦-share-a-reproduction-model) sections of the Reproduction toolkit show
> the commands, with a video of the interactive bootstrap. This page goes further: what each command generates or
> checks under the hood, the gotchas, a hands-on lab and recipes for support cases.

| You want | Command |
| --- | --- |
| a new model from an example, with menus | `playground repro bootstrap` |
| a new model from the connector config the customer sent (CFK, Strimzi, terraform, `.properties`, REST dump, JSON) | `playground repro bootstrap --config <file> -d "<case> <symptom>" --no-run` |
| the same, without menus (scripts, AI agents) | `playground repro bootstrap -f "<absolute path of the example>" -d "<case number> <symptom>" --no-run` |
| to end the scenario with its verdict, 🐞 reproduced or ✅ not reproduced | `playground repro assert --reproduced-if-log "<error>"` (or `--reproduced-if-connector-state FAILED`, `--reproduced-if-records-less-than N --topic <t>`, `--reproduced-if-command "…"`) |
| which version introduced or fixed it | `playground repro bisect --from <version> --to <version>` (binary search over the Confluent Hub versions), `--connector-tag A --connector-tag B`, or `--tag A --tag B` for CP |
| to say what it proves, and what came out of it | `playground repro status --expected "…" --actual "…" --jira CC-1234 --set "fixed in 10.8.3"` |
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
     `🔗 github file url`, `🌐 documentation`, and under `💬 comments:` the fields `🎯 expected`, `💥 actual`,
     `🎫 jira` and `🩹 status` (see "The fields of the header" in section 2),
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
playground repro bootstrap -f "…/http_no_auth.sh" -d "123456 dlq not working" --no-run \
  --expected "records with a bad schema go to the DLQ" --actual "the task fails with Unknown magic byte" --jira CC-1234
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

### From the config the customer sent: `--config`

Most cases start with a connector config: a CFK `Connector` resource, a Strimzi `KafkaConnector`, a terraform
`confluent_connector`, a `connect-standalone` `.properties`, a `GET /connectors?expand=info` dump or plain JSON (the
formats of [`connector convert`](/deep-dive-connector-create-or-update.md)). `--config` puts it in the model instead of
the one of the example:

```bash
playground repro bootstrap --config ~/Downloads/customer-connector.yaml -d "123456 dlq not working" --no-run
# 📄 --config: CFK Connector custom resource (spec.class, spec.taskMax, spec.configs), connector orders-to-mysql, connector.class io.confluent.connect.jdbc.JdbcSinkConnector
# 🔖 example to start from: connect/connect-jdbc-mysql-sink/mysql-sink.sh (-f to pick another one)
#    other examples that deploy io.confluent.connect.jdbc.JdbcSinkConnector:
#      connect/connect-jdbc-mysql-sink/mysql-sink-ssl.sh
#      …
# 🔧 adapted to the playground (--no-adapt to keep the config as is):
#    value.converter.schema.registry.url: https://sr.corp.internal:8081 → http://schema-registry:8081
# 📄 the connector config of the example is replaced with the one of customer-connector.yaml
#    values of the example kept (they point to its systems): connection.url topics
#    left out (systems of the customer the example does not use): connection.user connection.password
```

With menus (`playground repro bootstrap`, no `-f` nor `--config`), the first menu asks whether to start from an example
or from the connector config: the files that hold a `connector.class`, a `Connector` / `KafkaConnector` resource or a
`confluent_connector` resource are listed, newest first, with a preview. They come from the folders of
`playground config folder_zip_or_jar` (your home folder by default) and the current folder, 3 levels deep, and from
`~/Downloads` and `~/Desktop`, 5 levels deep (archived downloads, `SendSafely_download_*` folders). When none is found,
type, paste or drag the file onto the terminal. `--config <tab>` uses the same list.

1. **The example to start from.** Without `-f`, it is one that deploys the same `connector.class`, ranked with the
   words of the class (`S3SinkConnector`: s3, sink) and of the config (the database of a `jdbc:` url, the
   `auth.type`, an Avro / Protobuf / JSON Schema converter) found in its path. `--no-run` takes the best one and lists
   the next ones; with menus, you pick it. A fully managed class (`S3_SINK`) picks a `ccloud/fm-*` example.
2. **The connector heredoc of the example** that deploys the same class (else the first one) is replaced. Its command
   line stays (`--connector <name of the example>`, `--package … --level DEBUG`, `--wait`): the rest of the scenario
   uses that name. The config is adapted to the playground like `create-or-update` does (schema registry, bootstrap
   servers, license, replication factors).
3. **Behaviour from the customer, systems from the example.** The keys that say *how* the connector works
   (`insert.mode`, `pk.mode`, transforms, converters, error handling, `tasks.max`…) come from the customer. The keys
   that say *where* (urls, hosts, ports, users, passwords, database / SID / PDB names, buckets, regions, `file`,
   topics and topic prefixes, the tables captured (`table.inclusion.regex`, `table.include.list`…), the topic names
   the scenario reads (`table.topic.name.template`, `redo.log.topic.name`), replication factors, Kafka
   authentication of a fully managed connector) keep the value
   of the example, which the producer, the containers and the checks of the scenario use. The customer keys of that
   kind that the example doesn't set are left out (the user and password of a MySQL example that puts them in the
   url), except the values just rewritten for the playground. Both lists are logged and written in a comment above
   the heredoc.
4. **Secrets never land in the model.** Values still needed that the example doesn't provide (masked `****`, config
   providers of the customer, terraform references, plaintext passwords) become `"${VAR}"`, and each variable gets
   the standard `<VAR> is not set` check at the top of the model, so that `playground run` loads it from
   [`playground secrets`](/deep-dive-secrets.md): `playground secrets set <VAR>` once.

Gotchas:

- The customer's topic and table selection is replaced with the example's (`topics` and `topics.regex` can't be both
  set, and the scenario creates its own tables and checks its own topics): when the regex or the topic name template
  is the problem, put it back by hand, and create the matching tables in the scenario.
- The original file isn't copied in the repository (customer data): keep it next to the case and compare once the
  model runs, `playground connector diff --connector <c> --file <file>`.
- `--config-connector <name>` picks one connector of a file that holds several (REST dump, several resources).

### The fields of the header: `repro status`

A model is only useful later if it says what it proves and what came out of it. Bootstrap writes four fields under
`# 💬 comments:`, one line each:

```bash
# 💬 comments:
# 🎯 expected: records with a bad schema go to the DLQ
# 💥 actual: the task fails with "Unknown magic byte"
# 🎫 jira: https://confluentinc.atlassian.net/browse/CC-1234
# 🩹 status: open
```

- `--expected`, `--actual` and `--jira` fill them at bootstrap (the menus ask for expected and actual after the
  description, enter skips). A Jira key (`CC-1234`) becomes its link. `🩹 status` starts at `open`.
- `playground repro status` prints them, with the description, case, author and base example, and suggests the command
  for the empty ones. `--set`, `--expected`, `--actual` and `--jira` update the lines, without opening the file:

  ```bash
  playground repro status -f <model> --set "fixed in 10.8.3"     # or: not a bug, customer config, workaround…
  playground repro status -f <model> --json | jq -r .status
  ```

- `repro export` copies the fields into `repro-manifest.json`, and `repro import` prints them, so whoever receives the
  bundle reads expected vs actual before running it.
- A model created before the fields existed gets the missing lines added after `# 💬 comments:` (in the order above,
  above the free text) the first time `repro status` sets one. Free text under the fields is kept.
- One line per field: line breaks in a value become spaces. Write the details as free comments under the fields.

### Its verdict: `repro assert`

The real output of a model is one sentence: the problem is there, or it isn't. `repro assert` ends the scenario with
that sentence, from the check that says the `💥 actual` is there:

```bash
playground repro assert --reproduced-if-log "Unknown magic byte"                         # a line of the connect logs (--container) matches
playground repro assert --reproduced-if-connector-state FAILED --connector http-sink     # the connector or a task is in this state
playground repro assert --reproduced-if-records-less-than 10 --topic orders              # records lost (more-than: duplicates, DLQ)
playground repro assert --reproduced-if-command "<shell test>" --message "rows missing in the table"
# 🐞 REPRODUCED: 3 line(s) of the connect logs match "Unknown magic byte" (CP 8.4.0, connector 10.8.0)
# ✅ NOT REPRODUCED: nothing FAILED in connector http-sink (connector RUNNING, task 0 RUNNING) (CP 8.4.0, connector 10.8.1)
```

- Bootstrap writes these lines, commented, at the end of the scenario: uncomment the one that fits.
- **Both verdicts exit with 0**: a model that doesn't reproduce on a version is a result, not an error, and the script
  goes on. The exit code is 1 only when the check can't run (no connector, a record count that fails, two checks).
- One check per call. To combine several, use `--reproduced-if-command` (a shell test of your own), or call it once per
  check: the last call is the verdict.
- Each verdict is kept with its date, CP and connector versions and environment, in `playground-repro-verdicts` at the
  root of the repository (local, git-ignored, never in a bundle). `repro status` shows the last one of the model,
  `repro export` writes it in `repro-manifest.json` (`last_verdict`) and `repro import` prints it, so the colleague who
  runs the bundle knows what to expect. The CP and connector versions are the ones of the run (`TAG`, `CONNECTOR_TAG`,
  or the `--connector-zip` / `--connector-jar` file): run it with `playground run -f <model>`.

### Which version: `repro bisect`

"Is it fixed in 2.14.5? Since when is it broken?" With a verdict at the end of the model, the question answers itself:
`repro bisect` runs the model once per version and reads the verdict of each run.

```bash
playground repro bisect --from 2.10.0 --to 2.14.10                       # Confluent Hub versions of the connector of the model
# 🔎 bisect over 51 confluentinc/kafka-connect-oracle-cdc version(s) of cdc-oracle19-cdb-table-repro-123456-raw-columns.sh: 2.10.0 2.10.1 2.10.2 … 2.14.9 2.14.10
#    binary search: the first and the last version, then the middle until the verdict changes (assumes it changes once)
# ▶️  --connector-tag 2.10.0: playground run -f …/cdc-oracle19-cdb-table-repro-123456-raw-columns.sh --connector-tag 2.10.0
#    📜 tail -f /tmp/playground-repro-bisect/cdc-oracle19-cdb-table-repro-123456-raw-columns-2.10.0.log
#    🐞 2.10.0: reproduced (9m12s): 2 line(s) of the connect logs match "RAW"
# …
# 📊 verdicts of cdc-oracle19-cdb-table-repro-123456-raw-columns.sh:
#    2.10.0         🐞 reproduced      9m12s    …
#    2.11.4         🐞 reproduced      9m40s    …
#    2.12.1         🐞 reproduced      9m05s    …
#    2.12.2         🐞 reproduced      9m21s    …
#    2.12.3         ✅ not reproduced   8m58s    …
#    2.12.4         ✅ not reproduced   9m10s    …
#    2.12.11        ✅ not reproduced   9m02s    …
#    2.14.10        ✅ not reproduced   9m33s    …
# 🔀 the verdict changes between 2.12.2 (reproduced) → 2.12.3 (not reproduced)
# 📰 what changed between 2.12.2 and 2.12.3:
#    🔢 v2.12.3 - 📅 release date: 2024-06-21
#       • CC-27216: Fixed the handling of RAW data type (up to 2000 bytes).
#       …

playground repro bisect --connector-tag 2.14.0 --connector-tag 2.14.5 --connector-tag 3.0.0   # these versions only
playground repro bisect --tag 7.9.0 --tag 8.2.0 --tag 8.4.0                                    # CP versions
playground repro bisect --from 2.12.0 --to 2.13.0 --all --tag 8.2.0                            # every version, on one CP version
```

- The model must end with `playground repro assert` (bisect refuses a model without it). Without `--file`, the current
  model is used.
- `--from` / `--to` read the versions of the connector of the model on Confluent Hub (`playground connector-plugin
  versions`) and do a **binary search**: 8 runs for 51 versions. It assumes the verdict changes once in the range:
  with the same verdict at both ends, it stops after 2 runs. `--all` runs every version of the range.
- A run that stops before `repro assert` (container that doesn't start, connector version that doesn't install) is
  `❓ no verdict`, with its exit code and log: a binary search stops there, narrow the range around it.
- For a Confluent plugin, the changelog between the two versions where the verdict changes is printed
  ([`connector-plugin changelog`](/deep-dive-connector-plugin.md)): the fix (or the regression) is usually in it.
- ⚠️ Each run is a `playground run` of the model: it stops the running environment, and takes the time of the model.
  The log of each run is in `/tmp/playground-repro-bisect/<model>-<version>.log` (the `tail -f` line is printed when
  it starts), the summary in `/tmp/playground-repro-bisect/<model>-<date>.json` (`--json` prints it). `--run-flags`
  passes other flags to every run (`--run-flags "--environment sasl-ssl"`).

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
| `repro-manifest.json`: per model the last `playground run` line (from `playground-run-history`, without `--cluster-creds`), case number, author, base example, the header fields (`expected`, `actual`, `jira`, `status`), credential **names**, external files; the playground commit; the sha256 of every file | credential values |

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
head -20 "$m"
# # 💡 description: 000000 deep dive lab
# # 🔮 ticket: https://confluent.zendesk.com/agent/tickets/000000        <- any 6 leading digits
# # 💬 comments:
# # 🎯 expected:
# # 💥 actual:
# # 🎫 jira:
# # 🩹 status: open
grep -n "docker-compose" "$m"
# 25:playground start-environment --environment "${PLAYGROUND_ENVIRONMENT}" --docker-compose-override-file "${PWD}/docker-compose.plaintext.repro-000000-deep-dive-lab.yml"
grep -n "^exit 0" "$m"               # 114:exit 0 — the cheat sheet is above it, the snippets area below
ls -l reproduction-models/connect-connect-filestream-sink/README.md reproduction-models/connect-connect-filestream-sink/stop.sh
# README.md -> ../../connect/connect-filestream-sink/README.md
# stop.sh -> ../../connect/connect-filestream-sink/stop.sh
playground repro status -f "$PWD/$m" --set "lab only" --jira CC-1234
# ✏️  updated in the header: jira status
# 🔖 …/filestream-sink-repro-000000-deep-dive-lab.sh
#    💡 description: 000000 deep dive lab
#    🔮 ticket: https://confluent.zendesk.com/agent/tickets/000000
#    👤 author: you (Fri Oct 30 09:31:17 CET 2026)
#    🧬 based on: connect/connect-filestream-sink
# ❗    🎯 expected: (empty)
# ❗    💥 actual: (empty)
#    🎫 jira: https://confluentinc.atlassian.net/browse/CC-1234
#    🩹 status: lab only
#    🧪 last verdict: none yet (end the scenario with 'playground repro assert')
# 💡 fill in the empty fields: playground repro status -f …/filestream-sink-repro-000000-deep-dive-lab.sh --expected "…" --actual "…"
grep -n "^# playground repro assert" "$m"          # the verdict lines to uncomment, at the end of the scenario
playground repro assert -f "$PWD/$m" --reproduced-if-command "test -f '$PWD/$m'" --message "the model exists"
# 🐞 REPRODUCED: the model exists (the command succeeded: test -f '…') (CP default)       <- no container needed for this check
playground repro assert -f "$PWD/$m" --reproduced-if-command false; echo "exit=$?"
# ✅ NOT REPRODUCED: the command failed: false (CP default)
# exit=0
playground repro assert -f "$PWD/$m" --reproduced-if-command "test -f '$PWD/$m'"
playground repro status -f "$PWD/$m" | grep "🧪"
#    🧪 last verdict: 🐞 reproduced on 2026-10-30 (CP default): the command succeeded: test -f '…'
```

**Step 3: check it, with and without a secret**

```bash
playground repro check -f "$PWD/$m"
# 🕵️ scanning 3 file(s) of reproduction models for secrets and customer data
# 🔐 reading the 64 credentials known to this machine to look for their values (op backend)      <- ~10 s
# ✅ no secret nor customer data found
echo '# aws_access_key_id = AKIAABCDEFGHIJKLMNOP' >> "$m"          # a fake key, in the AWS format
playground repro check -f "$PWD/$m"; echo "exit=$?"
# 🔥    🔐 connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh:122 looks like an AWS access key id
# 🔥 ❌ 1 secret finding(s): remove them (use ${VAR} instead of the value)
# exit=1
playground repro check -f "$PWD/$m" --json | jq -c '.'
# {"files":3,"blocks":[{"location":"connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh:122","message":"looks like an AWS access key id"}],"warnings":[]}
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
tar xzOf /tmp/deep-dive-repro/playground_repro_*.tgz repro-manifest.json | jq -c '.models[0] | {script, case, base_example, jira, status, verdict: .last_verdict.verdict, run_command}'
# {"script":"connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab.sh","case":"000000","base_example":"connect/connect-filestream-sink","jira":"https://confluentinc.atlassian.net/browse/CC-1234","status":"lab only","verdict":"reproduced","run_command":"playground run -f {repro_dir}/filestream-sink-repro-000000-deep-dive-lab.sh"}
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

**Step 6: a model from the config the customer sent**

```bash
playground repro bootstrap --config "${PWD}/tools/connector-config/fixtures/cfk-filestream-sink.yaml" -d "000000 deep dive lab config" --no-run
# 📄 --config: CFK Connector custom resource (spec.class, spec.taskMax, spec.configs), connector filestream-cfk, connector.class org.apache.kafka.connect.file.FileStreamSinkConnector
# 🔖 example to start from: connect/connect-filestream-sink/filestream-sink.sh (-f to pick another one)
# 🔧 adapted to the playground (--no-adapt to keep the config as is):
#    - confluent.license
#    - value.converter.basic.auth.credentials.source
#    - value.converter.basic.auth.user.info
#    errors.deadletterqueue.topic.replication.factor: 3 → 1
#    value.converter.schema.registry.url: https://sr.prod.example.com:8081 → http://schema-registry:8081
# 📄 the connector config of the example is replaced with the one of cfk-filestream-sink.yaml
#    values of the example kept (they point to its systems): topics file
sed -n '/^# 📄/,/^EOF/p' reproduction-models/connect-connect-filestream-sink/filestream-sink-repro-000000-deep-dive-lab-config.sh
# playground connector create-or-update --connector filestream-sink --wait << EOF      <- the command line of the example
# {
#   "connector.class": "org.apache.kafka.connect.file.FileStreamSinkConnector",
#   "tasks.max": "1",
#   "topics": "filestream",                                    <- the example's
#   "file": "/tmp/output.json",                                <- the example's, the scenario reads it
#   …
#   "errors.tolerance": "all",                                 <- the customer's
#   "errors.deadletterqueue.topic.name": "dlq-cfk",
#   "errors.deadletterqueue.topic.replication.factor": "1",
#   "value.converter.schema.registry.url": "http://schema-registry:8081"
# }
# EOF
```

The license and the schema registry password of the customer are not in the model: `repro check` finds nothing.

**Step 7: clean up**

```bash
d=reproduction-models/connect-connect-filestream-sink
rm -f "$d/filestream-sink-repro-000000-deep-dive-lab.sh" \
      "$d/filestream-sink-repro-000000-deep-dive-lab-imported-$(date +%Y%m%d).sh" \
      "$d/docker-compose.plaintext.repro-000000-deep-dive-lab.yml" \
      "$d/filestream-sink-repro-000000-deep-dive-lab-config.sh" \
      "$d/docker-compose.plaintext.repro-000000-deep-dive-lab-config.yml"
rm -rf /tmp/deep-dive-repro
grep -vF "000000-deep-dive-lab" playground-repro-verdicts > /tmp/verdicts && mv /tmp/verdicts playground-repro-verdicts   # the lab verdicts
git -C reproduction-models status --short connect-connect-filestream-sink   # same as before the lab
```

Don't delete the symlinks of the folder: other models of the same example use them. The import made the lab model the
current one: run an example (or `playground state set run.test_file <script>`) before relying on `playground re-run`.

---

## 6. Recipes for support repros

| Situation | Command |
| --- | --- |
| a new case | `playground find-example "<connector> <feature>"`, then `repro bootstrap -f <best hit> -d "<case> <symptom>" --no-run`; also look for an earlier model of the same symptom in `reproduction-models/` |
| the customer gave a connector config | `repro bootstrap --config <their file> -d "<case> <symptom>" --no-run` (the example is picked from the class, secrets become variables), then once it runs `playground connector diff --connector <c> --file <their file>` (see the [`create-or-update` deep dive](/deep-dive-connector-create-or-update.md)) |
| the bug is fixed, or it turned out not to be one | `playground repro status -f <model> --set "fixed in <version>"` (`--jira CC-…`), or `--set "not a bug"` / `--set "customer config"` |
| say whether it reproduces | end the scenario with `playground repro assert --reproduced-if-…`: 🐞 / ✅ with the versions, kept for `repro status` and the bundle |
| the model must fail when the bug is fixed | assert at the end: `playground topic consume --min-expected-messages N --grep …`, or `connector create-or-update --wait` (see the [`topic consume` deep dive](/deep-dive-topic-consume.md)); `repro assert` reports instead of failing |
| hand it to engineering / a colleague | run it once (for the run line), `repro export --dry-run`, then `repro export` (`--include-artifacts` for a custom jar) and attach the bundle |
| a colleague sent you a bundle | `repro import --dry-run`, then `repro import`, then the printed `playground run` line |
| test the fix on another version | `playground run -f <model> --connector-tag <fixed version>`, or `playground update-version` on the running model |
| since when is it broken, which version fixed it | `repro bisect --from <version> --to <version>` (binary search, changelog of the version where the verdict changes) |
| a secret slipped in | replace it with `${VAR}` and `playground secrets set VAR …`; `repro check -f <model>` until it's clean |
| the commit is refused for a fake token | check the line it points to, then `git commit --no-verify` (only if it's not a real secret) |

Keep a model about one issue, fill in `🎯 expected` and `💥 actual` (and `🩹 status` once you know), use neutral names (topics, tables,
hosts) and never customer data.

---

## 7. Cheat sheet

```bash
playground repro bootstrap [-f "<absolute path of the example>" -d "<case> <symptom>" --no-run] \
  [--config <customer file> [--config-connector <name>]] [--expected "…"] [--actual "…"] [--jira CC-1234] [--custom-smt] [--connector-plugin <owner/name>] [--pipeline "<sink example>"]
playground repro status [-f <model>] [--set "<status>"] [--expected "…"] [--actual "…"] [--jira CC-1234] [--json]
playground repro assert --reproduced-if-log "<pattern>" [--container connect] | --reproduced-if-connector-state FAILED [--connector <c>] \
  | --reproduced-if-records-less-than|more-than <n> --topic <t> | --reproduced-if-command "<cmd>"   [--message "…"] [--json]
playground repro bisect [-f <model>] --from <v> --to <v> [--all] | --connector-tag A --connector-tag B … | --tag A --tag B …   [--tag <cp>] [--run-flags "…"] [--json]
playground repro check [-f <model> | --staged | --all] [--json] [--skip-secrets-store]
playground repro export [-f <model> … | --all-uncommitted] [--output <dir>] [--dry-run] [--include-artifacts] [--force] [--no-clipboard]
playground repro import -f <bundle.tgz> [--dry-run] [--on-conflict abort|rename|overwrite]
```

- Bootstrap = copy + header + own compose override + symlinks + cheat sheet. Scripts and agents: always `-f -d --no-run`.
- `--config <customer file>`: example picked from the class, its heredoc replaced, behaviour from the customer, systems from the example, secrets as `${VAR}`.
- `<script>-repro-<kebab description>.sh`; 6 leading digits = ticket link.
- Header fields `🎯 expected`, `💥 actual`, `🎫 jira`, `🩹 status`: set at bootstrap, read and updated by `repro status`, carried by the bundle.
- `repro assert`: 🐞 / ✅ verdict with the versions, exit 0 both, kept in `playground-repro-verdicts`, shown by `repro status`, carried by the bundle.
- `repro bisect`: one `playground run` per version (stops the environment), binary search with `--from` / `--to`, changelog where the verdict changes.
- Secrets: blocked by `check`, the pre-commit hook and `export`. Customer data: warned only.
- Bundle = files + symlinks as content + manifest (run line, credential names, sha256). Run the model once first.
- Import: identical skipped, conflicts abort unless `rename` / `overwrite`, first model becomes current.
- In a model, `create-or-update` warns instead of failing: `--wait` to make it strict.
- Sources: [`repro/bootstrap.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/bootstrap.sh),
  [`repro/status.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/status.sh),
  [`repro/assert.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/assert.sh),
  [`repro/bisect.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/bisect.sh),
  [`repro/check.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/check.sh),
  [`repro/export.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/export.sh),
  [`repro/import.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/repro/import.sh),
  [`scripts/repro-git-hooks/pre-commit`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/repro-git-hooks/pre-commit),
  helpers `repro_bundle_files` / `repro_bundle_scan` / `repro_install_git_hook` / `repro_header_set_value` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh).

---

**Links**

- 🎬 Video session: [🧪 The life of a reproduction model](/sessions?id=🧪-the-life-of-a-reproduction-model)
- 📖 [Bootstrap reproduction model](/reusables?id=🛠-bootstrap-reproduction-model) and
  [Share a reproduction model](/reusables?id=📦-share-a-reproduction-model) in the Reproduction toolkit
- 🍪 Deep dives: [`connector create-or-update`](/deep-dive-connector-create-or-update.md) (the warn-only wait of models),
  [`topic produce`](/deep-dive-topic-produce.md) and [`topic consume`](/deep-dive-topic-consume.md) (data in, assertions out)
- 🧠 CLI reference: [playground repro bootstrap](/playground%20repro%20bootstrap), [playground repro status](/playground%20repro%20status), [playground repro assert](/playground%20repro%20assert), [playground repro bisect](/playground%20repro%20bisect), [playground repro check](/playground%20repro%20check),
  [playground repro export](/playground%20repro%20export), [playground repro import](/playground%20repro%20import)
