# 🍪 Deep dive: connector plugins (`playground connector-plugin`)

The commands that answer the questions about a connector **plugin**, not a running connector: which versions exist and
when they were released, what a config key does and since which version, where the code of version X is (and what
changed between X and Y), and which jar ships a class. None of them needs a running environment: they read Confluent
Hub, GitHub, and the configuration references that CI records in this repository. Takes about 15 minutes to read and
run.

> [!TIP]
> In a hurry? Watch the short video session [🧑‍💻 The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version)
> first. This page goes further: where each answer comes from, its gotchas, a hands-on lab and recipes for support
> cases.

| You want | Command |
| --- | --- |
| one page on a plugin: license, latest version, how far behind, examples and CI, fully managed equivalents, links | `playground connector-plugin info -c confluentinc/kafka-connect-jdbc --from 10.7.4` (`--json`) |
| every released version, with its release date | `playground connector-plugin versions -c confluentinc/kafka-connect-jdbc` (`--last 5`, `--with-changelog`, `--json`) |
| how far behind the customer's version is | `playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --from 10.7.4` (`--latest` prints only the latest version) |
| what changed since version X (release notes), is a bug fixed after it | `playground connector-plugin changelog -c confluentinc/kafka-connect-jdbc --from 10.9.6` (`--grep "CVE\|NullPointer"`, `--to`, `--json`) |
| what was released on the Hub in the last days | `playground connector-plugin display-last-updated --days 7` (`--vendor confluentinc`, `--with-changelog`, `--json`) |
| what a config key does, its default, since when, values used | `playground connector-plugin config-key --key batch.size` (`-c JdbcSinkConnector`, `--since-version` for the exact version) |
| the config keys added, removed or changed between two versions (an upgrade) | `playground connector-plugin config-diff -c confluentinc/kafka-connect-jdbc --from 10.7.4` (`--file <customer config>`, `--json`) |
| the GitHub tree of the code at version X | `playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --only-show-url` |
| what changed between X and Y | the same with `--connector-tag 10.8.4 --connector-tag 10.9.9` |
| fully managed: the connector version of each cc-connect image, the first image with a fix, the commits between them | `playground connector-plugin fm-versions -c confluentinc/SalesforceBulkApiV2Sink` (`--find-first 3.2.1`, `--cc-connect-version`, `--with-log`; employees) |
| a local checkout of version X, to grep it | `… sourcecode … --connector-tag 10.8.4 --checkout-only` (the folder is the last line) |
| grep the code of version X | `… sourcecode … --connector-tag 10.8.4 --grep "BATCH_SIZE_DEFAULT"` (`file:line`, `--json`) |
| the commits / changed files between X and Y | `… sourcecode … --connector-tag 10.8.4 --connector-tag 10.9.9 --log` (`--grep "offset"`) / `--files` (`--path "*/JdbcSinkConfig.java"` for the diff) |
| the jars of the plugin, and which one has a class | `playground connector-plugin search-jar -c confluentinc/kafka-connect-s3 --class WebIdentityTokenCredentialsProvider` (`--connector-zip`, `--json`) |
| the libraries (and versions) a plugin version bundles, what changed between two versions | `playground connector-plugin dependencies -c confluentinc/kafka-connect-s3 --connector-tag 10.5.0 --grep jackson` (2× `--connector-tag` to compare, `--json`) |
| the known vulnerabilities (CVE) of a plugin version, fixed or not by another one | `playground connector-plugin cve-scan -c confluentinc/kafka-connect-jdbc --connector-tag 10.7.4 --compare-with 10.9.9` (`--severity high`, `--json`, HTML report) |
| the first plugin version shipping library X ≥ Y | `playground connector-plugin dependencies -c confluentinc/kafka-connect-jdbc --find-first postgresql:42.7.0` |
| the classes of the plugin that Connect loads from the worker instead | `playground connector-plugin search-jar -c confluentinc/kafka-connect-replicator --with-worker` |

Every subcommand takes `--json`, and `--connector-plugin` accepts `owner/name`, a connector class
(`io.confluent.connect.jdbc.JdbcSinkConnector`: its plugin is the one the examples of that class mount) or a fully
managed type (`S3_SINK` → `confluentinc/S3_SINK`).

---

## 1. Mental model (the 3 things to remember)

1. **Each answer has its own source, and its own freshness.**

   | Command | Source | Fresh as of |
   | --- | --- | --- |
   | `info` | Hub API (`/api/plugins/<owner>/<name>`), `versions`, the examples of the repository and their CI badges (`kafka-docker-playground.io/content.md`, cached one hour) | `versions` cache + now |
   | `versions` | Confluent Hub API (`api.hub.confluent.io/api/plugins/<owner>/<name>/versions`) | one day: the Hub answer is cached in `/tmp/version_<owner>_<name>.json` until `--force-refresh` |
   | `display-last-updated` | Confluent Hub API, one request listing every plugin with its latest version (`api.hub.confluent.io/api/plugins`) | now: not cached |
   | `changelog` | the changelog feeds of docs.confluent.io, one per minor line (`docs.confluent.io/kafka-connectors/<slug>/<major.minor>/changelog.xml`), found from the `documentation_url` of the plugin manifest; release dates from the Hub API | one day: cached in `/tmp/connector-plugin-changelog` until `--force-refresh` |
   | `config-diff`, `config-key --since-version` | the plugin version itself: downloaded (cache of `search-jar`), its connector loaded with the `java` of the connect image by `tools/connector-plugin-jars/ConfigDump.java` (compiled once in a JDK container), which prints its `ConfigDef` as `config/validate` would | kept per version in `.connector_config/` too |
   | `config-key` | the `config-<class>.txt` references next to the examples (about 290 files, tracked in git, refreshed by CI with the latest connector version), plus the versions you ran locally (`.connector_config/`) | your last `git pull` |
   | `sourcecode` | `scripts/cli/confluent-hub-plugin-list.txt` (plugin → repository), built from the Hub on first use; fully managed versions from `cc-docker-connect` | the list: until you regenerate it (`playground generate-connector-plugin-list`) |
   | `search-jar` | the plugin itself, downloaded with `confluent-hub install` in a throw-away container of the connect image | now (needs Docker, not an environment) |

2. **"Since when" is a CI date, not a release note.** `config-key` looks for the commit where the key first appeared
   in the recorded reference of that connector (`git log -S`). CI records the reference with the latest version it
   tests, so that date tells **roughly when a new connector version introduced the key**, not which version. For the
   exact version, add `--since-version`: it reads the configuration of the plugin versions themselves (binary search,
   no environment), like `config-diff` does.

3. **Self-managed and fully managed resolve versions differently.** A self-managed plugin (`confluentinc/kafka-connect-jdbc`,
   with a `-`) maps a Hub version to a GitHub tag (`v10.8.4`, with per-repository exceptions: Debezium `v<ver>.Final`,
   MongoDB `r<ver>`, Spooldir `kafka-connect-spooldir-<ver>`…). A fully managed one (`confluentinc/SalesforceBulkApiV2Sink`,
   no `-`) has no Hub version: `--connector-tag` is the **cc-connect image version** of the cluster, and the connector
   version is read from `cc-connect/cache-versions.env` of the private `confluentinc/cc-docker-connect` repository at
   that tag. That needs `GH_TOKEN` (or `GITHUB_TOKEN`) and the Confluent VPN. Without `--connector-tag`, the latest
   `cache-versions.env` is used. `fm-versions` reads that file over the cc-connect versions: which connector version each
   image ships, and the first image shipping a fix.

---

## 2. Versions: `versions`, `display-last-updated`

```bash
playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --last 3
# 💯 Listing last 3 versions for connector plugin confluentinc/kafka-connect-jdbc
# 🔢 v10.9.7 - 📅 release date: 2026-08-19 (64 days ago)
# 🔢 v10.9.8 - 📅 release date: 2026-09-16 (36 days ago)
# 🔢 v10.9.9 - 📅 release date: 2026-09-16 (36 days ago)
# 🌐 documentation: https://docs.confluent.io/kafka-connect-jdbc/current/

playground connector-plugin display-last-updated --days 7 --vendor confluentinc
```

Gotchas:

- **The list is cached for one day.** The answer of the Hub is kept in `/tmp/version_<owner>_<name>.json`; the
  "days ago" are computed on every call, so they are always right, but a release published in the last hours can be
  missing: use `--force-refresh` right after a release. When the Hub can't be reached, an older cache is used with
  `⚠️ could not refresh the versions of … using the cache of <date>`.
- `/tmp/version_<owner>_<name>` (no extension) is the text rendering, rewritten on every call: the `--connector-tag`
  picker and `repro bisect` read it.
- **`--from <customer version>`** prints how far behind it is, then only the newer versions:
  `📌 10.9.5 is 4 version(s) behind the latest 10.9.9 (released 2026-09-16, 44 days ago)`. At the latest version:
  `✅ … is the latest version`; a version the Hub doesn't know gets `⚠️ … is not a version of …` first. Add
  `--with-changelog` to read what changed since.
- **`--latest`** prints only the version number (`10.9.9`), for scripts. **`--json`** gives `latest`, `versions`
  (`version`, `release_date`, `days_ago`, `changes` with `--with-changelog`), `documentation_url`, and
  `from` / `versions_behind` with `--from` (counted before `--last`).
- Oldest first: `--last N` shows the N most recent, in release order, then the documentation link.
- `--with-changelog` adds the release notes of each version under it (same source and limits as `changelog` below):
  `versions -c confluentinc/kafka-connect-jdbc --last 3 --with-changelog`.
- The `--connector-tag` picker (`--connector-tag " "` of `run`, `update-version`, `sourcecode`, `search-jar`) shows the
  release notes of the highlighted version in its preview, for `confluentinc` plugins.
- `display-last-updated` makes one request to the Hub (a few seconds), newest first. It shows the **latest** version of
  each plugin only: a plugin released twice in the period appears once. `--vendor` is a regular expression on
  `owner/name`; a release date in the future (a vendor's typo) is skipped. `--with-changelog` adds the release notes of
  the new version of `confluentinc` plugins, `--json` gives `connector_plugin`, `version`, `release_date`, `days_ago`,
  `documentation_url` (and `changes`).
- A self-managed `playground run` can compute it in the background (last 3 days, `confluentinc`) and print it at the
  end: off by default, `playground config display-last-updated-connector-plugins true` turns it on,
  `display-last-updated-connector-plugins-days <n>` / `display-last-updated-connector-plugins-vendor <vendor|all>`
  change the window and the vendor (also in the `⚙️ CLI preferences` entry of the `playground run` menu).
- A version without a Hub release date prints `📅 release date: <unknown>`.

### One page on a plugin: `info`

```bash
playground connector-plugin info -c confluentinc/kafka-connect-jdbc --from 10.7.4
# 🔌 confluentinc/kafka-connect-jdbc: Kafka Connect JDBC
#    🏢 Confluent, Inc.   📜 Confluent Community License   🧩 source, sink
#    🔢 latest 10.9.9 (2026-09-16, 44 days ago), 119 version(s) since 2020-10-07
#    📌 10.7.4 is 30 version(s) behind the latest (playground connector-plugin changelog --connector-plugin confluentinc/kafka-connect-jdbc --from 10.7.4)
#    🐳 docker image: confluentinc/cp-kafka-connect
# 🧪 35 example(s) use it, CI: 24 🟢 ok, 0 🔴 fail, 11 🤷 not tested or unknown
#    🟢 connect/connect-jdbc-aws-redshift-source
#    …
#    🔌 connector classes: io.confluent.connect.jdbc.JdbcSinkConnector, io.confluent.connect.jdbc.JdbcSourceConnector
# ☁️ fully managed examples named like it (9 folder(s) with "jdbc"): IbmDb2Source, MicrosoftSqlServerSink, … PostgresSink, PostgresSource
# 🌐 documentation: https://docs.confluent.io/kafka-connect-jdbc/current/
# 📜 changelog: https://docs.confluent.io/kafka-connectors/jdbc/10.9/changelog.html
# 🧑‍💻 source code: https://github.com/confluentinc/kafka-connect-jdbc/tree/v10.9.9
```

Gotchas:

- **Examples** are the folders whose `docker-compose*.yml` mount the plugin (`confluent-hub-components/<owner>-<name>`),
  the private `reproduction-models` excluded. Their CI status comes from the badges of the published content page:
  `🤷` when the example isn't tested by CI or isn't listed there.
- **Connector classes** come from the `config-<class>.txt` of the examples that use this plugin only (an example with
  several plugins records the classes of the others too).
- **Fully managed** is a heuristic: the `ccloud/fm-*` folders whose name has every word of the plugin name (`jdbc`,
  `debezium postgresql`), and the types of their `config-<Type>.txt`. There is no mapping between a plugin and fully
  managed types: check it.
- `✅ requirements` only shows when the vendor filled it in the manifest (often empty, `null` for most Confluent
  plugins). A fully managed name (no `-`, like `confluentinc/SalesforceBulkApiV2Sink`) is refused: not on the Hub.
- `--json` gives every field (`examples[].ci`, `fully_managed.types`, `versions_behind`…).

### What changed: `changelog`

```bash
playground connector-plugin changelog -c confluentinc/kafka-connect-jdbc --from 10.9.6 --to 10.9.8
# 📜 Release notes of confluentinc/kafka-connect-jdbc after 10.9.6 up to 10.9.8: 2 version(s)
# 🔢 v10.9.8 - 📅 release date: 2026-09-16
#    • PR-1691 - Fix high CPU: JDBC source task busy-spins while waiting for table list
#    • PR-1678 - Guard stop() against a task whose start() never completed
#    • PR-1686 - fix: redact sensitive JDBC connector data reaching logs and task-status
# 🔢 v10.9.7 - 📅 release date: 2026-08-19
#    • PR-1679 - CC-43056: Bump org.postgresql:postgresql to 42.7.12 to address CVE-2026-54291
#    • PR-1669 - Enrich redacted JDBC sink SQL exception messages with non-sensitive diagnostic details
#    • PR-1665 - Redact sensitive values in JDBC sink SQL exception messages
# 🌐 changelog: https://docs.confluent.io/kafka-connectors/jdbc/10.9/changelog.html

# "is it fixed after the customer's version?"
playground connector-plugin changelog -c confluentinc/kafka-connect-jdbc --from 10.7.4 --grep "CVE"
```

Gotchas:

- `--from` is excluded, `--to` included (default: the latest on the Hub). Without `--from`, only the minor line of
  `--to` is shown. `--from` at the latest version prints `✅ … is the latest version`.
- **Only Confluent self-managed plugins documented under `docs.confluent.io/kafka-connectors/`** have a feed (about
  70 of the 80 on the Hub). The others print `⚠️ no changelog feed for …` and exit 0: partner plugins, Replicator,
  retired connectors. A fully managed type points to `fm-versions --with-log` (the commits between the connector
  versions of the cc-connect images); `sourcecode --log` gives the commits for the others.
- The feed URL is not in the manifest: it is derived from the manifest's `documentation_url` after its redirects
  (`docs.confluent.io/kafka-connect-jdbc/current/` → `kafka-connectors/jdbc/current/`).
- The notes are only as complete as the docs (`Updated hadoop and jose4j dependencies`). A match gives the version
  and the `CC-xxxxx` Jira id; confirm it in the code at that tag and the previous one (`sourcecode --connector-tag`).

---

## 3. Config keys: `config-key`

```bash
# every connector that has the key, with its type, default and importance
playground connector-plugin config-key --key flush.size

# one connector (part of its class name or fully managed type, case insensitive): the full doc
playground connector-plugin config-key --key batch.size -c io.confluent.connect.jdbc.JdbcSinkConnector
playground connector-plugin config-key -k s3.part.size -c S3_SINK
```

What it prints for one connector:

```text
🔑 batch.size in io.confluent.connect.jdbc.JdbcSinkConnector (group: Writes)
   Specifies how many records to attempt to batch together for insertion into the destination table, when possible.
   - Type: INT
   - Default: 3000
   - Importance: MEDIUM
   - Required: false
   📄 connect/connect-jdbc-ibmdb2-sink/config-io.confluent.connect.jdbc.JdbcSinkConnector.txt
   📅 present since CI first recorded this connector's configuration (2025-09-25)
   🗂️  versions run locally (default): 10.7.4 ✅ (3000) 10.9.0 ✅ (3000) … 10.9.9 ✅ (3000)
🧪 20 line(s) in examples set batch.size with connector io.confluent.connect.jdbc.JdbcSinkConnector, values used (most frequent first):
   "1"                            x4   e.g. reproduction-models/…/vertica-sink-repro-batch-size.sh:90
   "512"                          x3   e.g. connect/connect-jdbc-aws-redshift-sink/redshift-jdbc-sink.sh:138
   …
```

How to read it:

| Line | Meaning |
| --- | --- |
| `📅 present since CI first recorded …` | the key was already there in the first reference CI recorded: older than the recording, no date |
| `📅 first recorded by CI on <date> (commit <sha>)` | the key appeared in the reference on that date: a connector version released around then added it |
| `🗂️ versions run locally` | each version you ran (or listed with `show-config-parameters`) on this machine: ✅ with its default, ❌ when the key doesn't exist in that version |
| `🧪 … values used` | `"<key>": <value>` lines in the examples and repro models, most frequent value first, with one file to open |

Gotchas:

- **`--since-version`** finds the first version having the key, with the same reader as `config-diff` (binary search
  over the Hub versions, about 5 s per probed version):
  `📅 timestamp.precision.mode was added in confluentinc/kafka-connect-jdbc 10.8.3 (absent in 10.8.2)`. It needs one
  connector (`-c`); the plugin is the one the examples of that class mount, or `--connector-plugin`. "First" is in
  version order: with minor lines patched in parallel, check the line of the customer.
- **Framework keys are not in a plugin's reference**: `errors.tolerance`, `transforms.*`, `topics`, converters,
  `consumer.override.*`… are answered with `🧩 … is a Kafka Connect framework key, common to every connector` and the
  links to the Connect docs.
- **Without `-c`, details only when one connector has the key**: otherwise you get the table and a hint to narrow.
- **A key not found** exits 1 (`🤷 key batch.sise not found for connector JdbcSinkConnector`, then
  `🧪 no example sets batch.sise …`). Similar keys (`💡 similar keys`) are only suggested when the key is close to an
  existing one by name: a one-letter typo like `batch.sise` got no suggestion.
- `🗂️ … only found in versions of <class> run locally` means CI doesn't record it (any more): removed in the
  version CI tests, or a connector CI doesn't run.
- Fully managed connectors are listed under their type (`S3_SINK`, `AzureBlobSink`), self-managed under their class:
  the same key often shows both, with different defaults (`flush.size`: `1000` fully managed, `null` self-managed).

---

### What an upgrade changes in the configuration: `config-diff`

```bash
playground connector-plugin config-diff -c confluentinc/kafka-connect-jdbc --from 10.7.4
# 🔧 io.confluent.connect.jdbc.JdbcSinkConnector 10.7.4 → 10.9.9: 22 → 29 keys, 7 change(s)
#    ➕ date.calendar.system (STRING, default LEGACY, LOW): Conversion of time since epoch value …
#    ➕ timestamp.precision.mode (STRING, default MICROSECONDS, LOW): Convert the Timestamp with precision. …
#    …
# 🔧 io.confluent.connect.jdbc.JdbcSourceConnector 10.7.4 → 10.9.9: 31 → 40 keys, 11 change(s)
#    ➕ poll.linger.ms (LONG, default 5000, LOW): The maximum time to wait for a record before returning an empty batch. …
#    …
#    ✏️ batch.max.rows: default 100 → 1000
#    🔀 timestamp.granularity: valid_values [connect_logical, nanos_long, …] → [connect_logical, micros_long, …]

# only the keys of the customer's config (JSON, CFK, Strimzi, terraform, properties)
playground connector-plugin config-diff -c confluentinc/kafka-connect-jdbc --from 10.7.4 --file customer.json
# 🔧 io.confluent.connect.jdbc.JdbcSourceConnector 10.7.4 → 10.9.9: 31 → 40 keys, 1 change(s), among the 9 keys of customer.json
#    ✏️ batch.max.rows: default 100 → 1000
```

| Line | Meaning |
| --- | --- |
| `➕` / `➖` | key added / removed, with its type, default and importance |
| `✏️ <key>: default A → B` | the default changed: a config that doesn't set the key behaves differently after the upgrade |
| `🔀 <key>: type / importance / valid_values / required A → B` | the definition changed |
| `📝 <key>: documentation changed` | with `--with-docs` |
| `❗ <key> is set in <file> but <class> <to> doesn't know it` | with `--file`: removed, renamed, or a typo |

Gotchas:

- **No environment, but Docker**: each version is downloaded once, then its connector is loaded in the connect image
  (`--tag` of the playground, or the running `connect`) by a small reader compiled once in an `eclipse-temurin` JDK
  container. About 10 s for two new versions, instant after.
- It is the configuration of the plugin (its `ConfigDef`), like the references CI records: the framework keys
  (`errors.*`, `transforms`, converters…) are not in it.
- Every connector class of the plugin is compared (from its `META-INF/services`, else the classes named `*Connector`),
  or `--connector-class`, or the `connector.class` of `--file`.
- A validator that only prints an object identity (`Class$1@6438a396`) has no `valid_values`: no false change.
- Each version read is also written to `.connector_config/` like `connector show-config-parameters`: `config-key` lists
  it in `🗂️ versions run locally` (dated in the past, so that `connector diff` keeps using the reference of the running
  version).

## 4. Source code: `sourcecode`, `fm-versions`

```bash
# the GitHub tree at the exact tag (no browser with --only-show-url)
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --only-show-url

# what changed between two versions: GitHub's compare view
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --connector-tag 10.9.9 --only-show-url

# a local checkout, reused on the next call, path on the last line
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --checkout-only

# fully managed (Confluent employees: GH_TOKEN + VPN): --connector-tag is the cc-connect image version
GH_TOKEN=… playground connector-plugin sourcecode -c confluentinc/SalesforceBulkApiV2Sink --connector-tag <cc-connect version> --only-show-url
```

| Flag | Does | Interactive |
| --- | --- | --- |
| *(none)* | opens the URL in your browser (`open`), prints it when there is no `open` command | browser |
| `--only-show-url` | prints the URL | no |
| `--checkout-only` | `git clone --depth 1 --branch <tag>` into `/tmp/connector-plugin-sourcecode/<repo>-<version>`, reused if it exists, prints the folder last | no |
| `--open` | the same checkout, then opens it in `playground config get editor` | editor; asks whether to delete an existing checkout |
| `--compile` | the checkout, then a Maven build in Docker (JDK from `pom.xml`, or `--compile-jdk-version`), prints the zip | asks before recompiling; Confluent repositories need `dev-login` and AWS credentials |
| `--connector-tag " "` | pick the version in an fzf menu | yes (self-managed only) |
| `--grep <regex>` (one version) | the checkout, then `file:line` of every match (500 at most) | no |
| `--log` (two versions) | the commits between the two tags, newest first, merge commits left out; `--grep` filters the messages | no |
| `--files` (two versions) | the changed files with `+/-`; `--path <glob>` keeps some of them and prints their diff | no |
| `--json` | the URL, checkout folder, commits, files or matches as JSON (logs on stderr) | no |

Gotchas:

- **Scripts and agents: `--only-show-url` or `--checkout-only`, never `--open` / `--compile`.** They open an editor or
  ask questions (an existing folder, recompile?), and wait.
- **Without `--connector-tag`, the latest Hub version** is used (`✨ --connector-tag was not set, using latest version
  on hub 12.1.13`), not the version the customer runs: always pass theirs.
- **The checkout is shallow** (`--depth 1`): `git log` inside has one commit. For the history between two versions, use
  `--log` / `--files`.
- **`--log` and `--files` call the GitHub compare API**: through `gh` when it is logged in, else with `GH_TOKEN` /
  `GITHUB_TOKEN` when set, else anonymously (60 requests per hour). Private repositories (proprietary and fully managed
  connectors) need a token. Up to 1000 commits and files are read. `--log` is what the release notes don't say (refactors,
  reverts, the commits of a backport); the release notes say what was released, check both.
- **A checkout emptied by the cleanup of `/tmp`** (macOS deletes the files untouched for 3 days, keeps the folders) is
  cloned again: `📂 the checkout in … is incomplete (files deleted by the cleanup of /tmp?), cloning it again`.
- **The plugin list decides the repository.** `scripts/cli/confluent-hub-plugin-list.txt` maps each plugin to its
  source URL; it's generated from the Hub on first use, and Confluent employees get the private mapping (proprietary
  connectors, fully managed types) when AWS credentials are set (`👽 # CONFLUENT EMPLOYEE VERSION` on top). A plugin
  without source URL: `🤷‍♂️ could not found sourcecode url for plugin …. It is probably proprietary`.
- **Fully managed plugins need the employee version of the list**: without it, `sourcecode` stops with
  `playground connector-plugin sourcecode is not working with fully managed connectors`. Self-managed plugins work with
  the public list.
- Some repositories hold several connectors: `confluentinc/kafka-connect-s3` is in `kafka-connect-storage-cloud`, the
  fully managed Salesforce types in `kafka-connect-salesforce`. The URL is the repository at the tag: find the
  connector's module inside.

### Fully managed connector versions: `fm-versions`

Fully managed connectors have no Hub versions: each image of the cc-connect service (a tag of the private
`confluentinc/cc-docker-connect` repository) pins one version of every connector in `cc-connect/cache-versions.env`.
`fm-versions` reads that file over the tags (Confluent employees):

```bash
# the last 10 cc-connect versions (--last N), grouped by connector version, newest first
playground connector-plugin fm-versions -c confluentinc/SalesforceBulkApiV2Sink
# the same, with the commits between two connector versions (sourcecode --log under the hood)
playground connector-plugin fm-versions -c confluentinc/SalesforceBulkApiV2Sink --last 50 --with-log
# the connector version one image ships
playground connector-plugin fm-versions -c confluentinc/S3_SINK --cc-connect-version 0.3780.0
# the first image shipping at least a connector version: "is the fix of 3.2.1 in an image yet?"
playground connector-plugin fm-versions -c confluentinc/SalesforceBulkApiV2Sink --find-first 3.2.1
```

What it prints (from the lab, step 6):

```text
☁️ confluentinc/SalesforceBulkApiV2Sink (SALESFORCE_CONNECTOR_VERSION) in the last 250 cc-connect versions, newest first
   0.3730.0 … 0.3785.0  →  3.2.0-rc-4be74dd8-cloud
   0.3710.0 … 0.3729.0  →  3.2.0-rc-7b0f5ae9-cloud
   0.3683.0 … 0.3709.0  →  3.2.0-rc-6f27adbb-cloud
   0.3682.5 … 0.3682.7  →  3.2.0-rc-7b0f5ae9-cloud      <- a rollback
```

Gotchas:

- **Needs `gh` logged in (or `GH_TOKEN`), the VPN, and the employee plugin list** (it maps the type to its variable in
  `cache-versions.env`, `SALESFORCE_CONNECTOR_VERSION`; `playground generate-connector-plugin-list` with AWS
  credentials). `-c` also takes a fully managed type (`S3_SINK`) or a connector class.
- The tags are listed once a day (about 30 s); each version's `cache-versions.env` is cached forever in
  `/tmp/connector-plugin-fm` (a tag doesn't move): a first `--last 250` takes about a minute.
- `--find-first 3.2.1` compares the numeric part of the connector versions (`3.2.0-rc-4be74dd8-cloud` → `3.2.0`), by
  binary search: rollbacks between rc builds of the same version don't change the answer.
- **An image version is not a deployment**: which cc-connect version a cluster runs is in its connect logs (chewie).
  `fm-versions` says which image has the fix, not whether the customer's cluster runs it.
- To read the code of the connector version an image ships: `sourcecode -c confluentinc/<Type> --connector-tag <cc-connect
  version> --only-show-url` (see above).

---

## 5. Jars: `search-jar`

```bash
playground connector-plugin search-jar -c confluentinc/kafka-connect-s3 --class WebIdentityTokenCredentialsProvider
playground connector-plugin search-jar -c confluentinc/kafka-connect-s3 --connector-tag 10.5.0 --class WebIdentityTokenCredentialsProvider

# the classes Connect loads from the worker instead of the plugin
playground connector-plugin search-jar -c confluentinc/kafka-connect-replicator --with-worker

# a customer's zip, a class on both sides with the signatures of each copy
playground connector-plugin search-jar --connector-zip /path/to/plugin.zip --class org.apache.kafka.clients.producer.KafkaProducer --with-worker
```

It installs the plugin (the latest version on the Hub, or `--connector-tag`) in a throw-away container of the connect
image, or extracts `--connector-zip`, keeps it in `/tmp/connector-plugin-jars/<owner>-<name>-<version>/` (reused on
the next call, `--force-refresh`), and lists the jars of its `lib/`. With `--class`, it prints the classes with that
name, the jar they're in, and their method signatures (`javap`).

```text
🤎 18 jar(s), 5509 classes in /tmp/connector-plugin-jars/confluentinc-kafka-connect-jdbc-10.8.4/confluentinc-kafka-connect-jdbc/lib
…
🔎 1 class(es) named PostgreSqlDatabaseDialect in the jars of confluentinc/kafka-connect-jdbc:10.8.4
   👉 io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect in kafka-connect-jdbc-10.8.4.jar

☕ io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect (kafka-connect-jdbc-10.8.4.jar):
public class io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect extends io.confluent.connect.jdbc.dialect.GenericDatabaseDialect { …
```

**`--with-worker`** compares the plugin with the worker classpath of the connect image (the running `connect`
container, else the default image), indexed once per image in `/tmp/connector-plugin-jars/worker-<image>-<tag>.tsv`:

```text
⚠️ 3517 class(es) of the plugin are ignored: Connect loads them from the worker (org.apache.kafka.*, org.slf4j.*, java*…) in another version, …
   ⚠️ kafka-streams-8.4.0-ccs.jar ↔ worker kafka-streams-8.4.0-ce.jar: 1158 class(es), e.g. org.apache.kafka.streams.AutoOffsetReset
   …
ℹ️ 123483 other class(es) are on both sides: the plugin uses its own copy (plugin isolation), top jars:
   • scala-library-2.13.11.jar ↔ worker scala-library-2.13.18.jar: 2885 class(es)
```

| Line | Meaning |
| --- | --- |
| `⚠️ … ignored: Connect loads them from the worker` | classes matching the parent-first rules of the worker's plugin isolation (`org.apache.kafka.*` except the transforms, converters…, `org.slf4j.*`, `java*`): the plugin's copy is never used. When the plugin was built against another version, that's a `NoSuchMethodError` / `NoClassDefFoundError` / `LinkageError` |
| `✅ … loaded from the same jar of the worker` | same jar on both sides (often `slf4j-api`): harmless |
| `💥 … also on the worker, in packages that the worker config hands to the … clients of the tasks` | classes the plugin keeps in isolation, but that the **worker config** puts into the producer / consumer / admin clients the task builds inside the plugin classloader: `io.confluent.telemetry.*` (`metric.reporters` with the Confluent Telemetry Reporter), `io.confluent.metrics.reporter.*`, the monitoring interceptors, `io.confluent.kafka.clients.plugins.*` / `io.confluent.security.auth.client.*` (`sasl.login.callback.handler.class`). When the worker sets that config, the client gets one class from each loader: `class X is not an instance of Y`, `ClassCastException`, `LinkageError`, even with identical signatures |
| `ℹ️ … other class(es) are on both sides` | the plugin uses its own copy, isolated from the worker's: no conflict, listed for information |

For example, the replicator plugin ships its own `telemetry-events` jar, so its tasks fail as soon as the worker
enables the Telemetry Reporter
([#9256](https://github.com/vdesabou/kafka-docker-playground/issues/9256)):

```text
💥 140 class(es) of the plugin are also on the worker, in packages that the worker config hands to the producer / consumer / admin clients of the tasks: …
   💥 io.confluent.telemetry.*: 140 class(es), set by metric.reporters (Confluent Telemetry Reporter), confluent.telemetry.*
      • telemetry-events-8.3.2-ce.jar ↔ worker ce-events_ce-events-project.jar: 42 class(es), e.g. io.confluent.telemetry.NamedConfigUtils
```

With `--class`, such a class gets `💥 also on the worker, and handed to the clients of the tasks by the worker config`.

The rules are read from `PluginUtils` in the image itself, so they follow the CP version. With `--class`, the worker's
copies of the class are listed too, with their signatures: compare them with the plugin's.

Gotchas:

- `--class` is **exact first**: a simple name (`PostgreSqlDatabaseDialect`, or the inner class name) or a fully qualified
  name. When no class has that name, the classes containing it (case insensitive) are listed:
  `🔎 no class named exactly Dialect: 33 class(es) contain it`. Signatures are printed for 5 classes at most.
- Needs Docker (not a running environment) and `python3`. Without a local JDK, `javap` runs in an
  `eclipse-temurin:21-jdk` container (`PG_JAVAP_IMAGE` to change it).
- Without `--with-worker`, it's the plugin's own `lib/` only: classes that come from the worker (Kafka, Connect API,
  the converters of the image) are not there.
- `--json` gives `jars`, `matches` (`class`, `jar`, `signatures`, `loaded_from_worker`), `worker_matches` and
  `worker` (`shadowed`, `isolated_duplicates`, with `same_jar`, and `worker_config_conflicts`: `package`, `settings`,
  `nb_classes`, `jars`); a match of `--class` in one of those packages has `worker_config_conflict`.

---

### Libraries: `dependencies`

```bash
playground connector-plugin dependencies -c confluentinc/kafka-connect-s3 --connector-tag 10.5.0 --grep "jackson-databind"
# 📚 3 librar(y/ies) in confluentinc/kafka-connect-s3:10.5.0 matching "jackson-databind"
# com.fasterxml.jackson.core:jackson-databind  2.13.4.2  jackson-databind-2.13.4.2.jar
# com.fasterxml.jackson.core:jackson-databind  2.13.4.2  inside kafka-connect-storage-common-htrace-core4-shaded-11.0.20.jar
# com.fasterxml.jackson.core:jackson-databind  2.13.4.2  inside kafka-connect-storage-format-11.0.20.jar

playground connector-plugin dependencies -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --connector-tag 10.9.9
# 📚 confluentinc/kafka-connect-jdbc:10.8.4 → confluentinc/kafka-connect-jdbc:10.9.9: 6 change(s), 14 librar(y/ies) unchanged
# ⬆️   mssql-jdbc          8.4.1 → 12.8.2
# ⬆️   postgresql          42.4.4 → 42.7.12
# ➕  jsqlparser          4.9
# ➖  checker-qual        3.5.0
# …

playground connector-plugin dependencies -c confluentinc/kafka-connect-jdbc --connector-tag 10.7.0 --find-first postgresql:42.7.0
#    🔍 confluentinc/kafka-connect-jdbc 10.9.9: postgresql 42.7.12 ✅
#    🔍 confluentinc/kafka-connect-jdbc 10.8.5: postgresql 42.4.4
#    …
# ✅ confluentinc/kafka-connect-jdbc 10.9.4 is the first version shipping postgresql ≥ 42.7.0 (42.7.11)
```

Same download and cache as `search-jar`. Each library comes from the `META-INF/maven/<group>/<artifact>/pom.properties`
of the jars, or from the jar file name when there is none (no group then).

Gotchas:

- **Shaded copies count**: a fat jar holds the `pom.properties` of the libraries shaded inside it, listed as
  `inside <jar>`. That's what a CVE scanner sees too: a library can be fixed in its own jar and still old inside
  another. In a diff, the library's own jar wins over a shaded copy.
- **`--find-first` is a binary search in version order** (previews and release candidates left out) from the first
  `--connector-tag`, or the oldest version: each probed version is downloaded once (about 5 s each, 6 probes for 35
  versions). When several minor lines are patched in parallel, the answer is the first version in version order, not
  the first release date: start from the customer's line with `--connector-tag`. Cross-check with
  `changelog --grep <library>` (`PR-1635 - Bump org.postgresql:postgresql to 42.7.11 (CVE-…)`).
- `--connector-zip` with one `--connector-tag` compares a customer's zip with a Hub version.

### Vulnerabilities: `cve-scan`

```bash
playground connector-plugin cve-scan -c confluentinc/kafka-connect-jdbc --connector-tag 10.7.4 --compare-with 10.9.9
# 🛡️ confluentinc/kafka-connect-jdbc:10.7.4: 3 known vulnerabilit(y/ies), confluentinc/kafka-connect-jdbc:10.9.9: 0
# ✅ 3 fixed by confluentinc/kafka-connect-jdbc:10.9.9:
#    🔴 CVE-2024-1597 Critical postgresql 42.4.3 (fixed in 42.4.4) in postgresql-42.4.3.jar   📜 release notes of 10.7.5
#    🟠 CVE-2025-59250 High mssql-jdbc 8.4.1 (fixed in 10.2.4.jre11) in mssql-jdbc-8.4.1.jre8.jar   📜 release notes of 10.9.1
#    🟠 CVE-2026-42198 High postgresql 42.4.3 (fixed in 42.7.11) in postgresql-42.4.3.jar   📜 release notes of 10.9.4
# ⚠️ 0 still in confluentinc/kafka-connect-jdbc:10.9.9:
# ⚠️ what a scanner sees in the jars, not an official Confluent statement: …
# ✅ HTML report saved: /tmp/playground-cve-scan/cve-scan-…html
```

The jars of each version (cache of `search-jar`) are scanned with [grype](https://github.com/anchore/grype) in Docker;
for Confluent plugins, the CVE ids fixed between the two versions are looked up in their release notes (`📜`).

Gotchas:

- **A scanner result is not an official statement**: a vulnerable library can be unused, or its vulnerable code
  unreachable in the connector. Use it to answer "which version removes the jar the customer's scanner flags", and
  point to the Confluent security advisories for the official position.
- The first scan downloads the grype database (a minute or two), kept in the `kdp-grype-db` docker volume; a scan is
  kept one day next to the jars (the database changes daily, `--force-refresh`). `PG_CVE_SCANNER_IMAGE` changes the
  image.
- The libraries shaded inside fat jars are scanned too (the location shows the jar they're in). The id is the CVE when
  there is one, else the GitHub advisory (`GHSA-…`), the other ids in `aliases` (`--json`).
- `--severity high` keeps High and Critical. `--connector-zip` scans a customer's zip (no `--compare-with` then).

## 6. Hands-on lab (≈10 min, no environment needed)

Steps 1 to 4 need internet access only; step 5 needs Docker; step 6 is for Confluent employees (`GH_TOKEN` + VPN).

**Step 1: versions, the cache, and what changed**

```bash
playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --last 3
# 💯 Listing last 3 versions for connector plugin confluentinc/kafka-connect-jdbc
# 🔢 v10.9.7 - 📅 release date: 2026-08-19 (64 days ago)
# 🔢 v10.9.8 - 📅 release date: 2026-09-16 (36 days ago)
# 🔢 v10.9.9 - 📅 release date: 2026-09-16 (36 days ago)
# 🌐 documentation: https://docs.confluent.io/kafka-connect-jdbc/current/
ls -l /tmp/version_confluentinc_kafka-connect-jdbc.json                                 # the cache (one day)
playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --from 10.9.5 --last 2
# 📌 10.9.5 is 4 version(s) behind the latest 10.9.9 (released 2026-09-16, 44 days ago)
# 🔢 v10.9.8 - 📅 release date: 2026-09-16 (44 days ago)
# 🔢 v10.9.9 - 📅 release date: 2026-09-16 (44 days ago)
playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --latest
# 10.9.9
playground connector-plugin changelog -c confluentinc/kafka-connect-jdbc --from 10.9.6 --to 10.9.8
# 📜 Release notes of confluentinc/kafka-connect-jdbc after 10.9.6 up to 10.9.8: 2 version(s)
# 🔢 v10.9.8 - 📅 release date: 2026-09-16
#    • PR-1691 - Fix high CPU: JDBC source task busy-spins while waiting for table list
# …
# 🌐 changelog: https://docs.confluent.io/kafka-connectors/jdbc/10.9/changelog.html
```

**Step 2: a config key, everywhere then for one connector**

```bash
playground connector-plugin config-key --key flush.size
# 🔌 12 connector(s) have key flush.size, use --connector-class to see the details of one
#    defaults: null (x7), 1000 (x5)
# CONNECTOR                                                       TYPE  DEFAULT  IMPORTANCE
# AzureBlobSink                                                   INT   1000     HIGH
# …
# io.confluent.connect.s3.S3SinkConnector                         INT   null     HIGH
# 🧪 428 line(s) in examples set flush.size, values used (most frequent first):
#    "3"   x275 …
playground connector-plugin config-key --key batch.size -c io.confluent.connect.jdbc.JdbcSinkConnector
# 🔑 batch.size in io.confluent.connect.jdbc.JdbcSinkConnector (group: Writes) … - Default: 3000
```

**Step 3: framework keys and typos**

```bash
playground connector-plugin config-key --key errors.tolerance -c JdbcSinkConnector
# 🧩 errors.tolerance is a Kafka Connect framework key, common to every connector: JdbcSinkConnector does not list it in its own configuration
#    📗 https://docs.confluent.io/platform/current/installation/configuration/connect/sink-connect-configs.html …
# 🧪 100 line(s) in examples set errors.tolerance …: "all" x98, "none" x2
playground connector-plugin config-key --key batch.sise -c JdbcSinkConnector; echo "exit=$?"
# 🤷 key batch.sise not found for connector JdbcSinkConnector
# 🧪 no example sets batch.sise with connector JdbcSinkConnector
# exit=1
```

**Step 4: the code at the customer's version, and what changed**

```bash
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --only-show-url
# 🧑‍💻🌐 sourcecode for plugin confluentinc/kafka-connect-jdbc for 10.8.4 version is available at:
# https://github.com/confluentinc/kafka-connect-jdbc/tree/v10.8.4
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --connector-tag 10.9.9 --only-show-url
# ✨ --connector-tag flag is set 2 times, comparison mode will be opened with versions v10.8.4 and v10.9.9
# https://github.com/confluentinc/kafka-connect-jdbc/compare/v10.8.4...v10.9.9
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --checkout-only | tail -1
# /tmp/connector-plugin-sourcecode/kafka-connect-jdbc-10.8.4        <- 2 s the first time, then reused (0.5 s)
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --grep "BATCH_SIZE_DEFAULT ="
# 🔎 1 match(es) for "BATCH_SIZE_DEFAULT =" in /tmp/connector-plugin-sourcecode/kafka-connect-jdbc-10.8.4
# src/main/java/io/confluent/connect/jdbc/sink/JdbcSinkConfig.java:145:  private static final int BATCH_SIZE_DEFAULT = 3000;
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.9.3 --connector-tag 10.9.5 --log --grep "postgres"
# 📜 3 commit(s) from v10.9.3 to v10.9.5 in github.com/confluentinc/kafka-connect-jdbc matching "postgres", newest first (11 merge commit(s) left out)
#    2026-06-11 8cc4c8977 Strip catalog from discovered TableIds in Postgres dialect (…)
#    2026-06-05 2aa9fbaff Revert - Bump org.postgresql:postgresql to 42.7.11 (CVE-2026-42198) [CC-41166] (#1646) (…)
#    2026-05-13 1624be0df Bump org.postgresql:postgresql to 42.7.11 (CVE-2026-42198) (…)
playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.9.7 --connector-tag 10.9.8 --files --path "*/JdbcSinkConfig.java"
# 🗂️ 1 file(s) changed from v10.9.7 to v10.9.8 matching */JdbcSinkConfig.java
#    M src/main/java/io/confluent/connect/jdbc/sink/JdbcSinkConfig.java +3 -0
# 📄 src/main/java/io/confluent/connect/jdbc/sink/JdbcSinkConfig.java
# @@ -337,6 +337,9 @@ …
```

**Step 5: which jar has a class (Docker)**

```bash
playground connector-plugin search-jar -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --class PostgreSqlDatabaseDialect
# 🔌 Downloading connector plugin confluentinc/kafka-connect-jdbc:10.8.4          <- only the first time
# 🤎 18 jar(s), 5509 classes in /tmp/connector-plugin-jars/confluentinc-kafka-connect-jdbc-10.8.4/confluentinc-kafka-connect-jdbc/lib
# … kafka-connect-jdbc-10.8.4.jar, mssql-jdbc-8.4.1.jre8.jar, ojdbc8-19.7.0.0.jar, postgresql-42.4.4.jar …
# 🔎 1 class(es) named PostgreSqlDatabaseDialect in the jars of confluentinc/kafka-connect-jdbc:10.8.4
#    👉 io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect in kafka-connect-jdbc-10.8.4.jar
# public class io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect extends io.confluent.connect.jdbc.dialect.GenericDatabaseDialect { …
playground connector-plugin search-jar -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --with-worker
# ✅ no class of the plugin is replaced by a different version from the worker confluentinc/cp-server-connect:8.4.0
#    ✅ slf4j-api-1.7.36.jar: 34 class(es) loaded from the same jar of the worker
```

**Step 6 (optional, Confluent employees): a fully managed connector** (not replayed by the lab: it needs the VPN and
private repositories)

```bash
GH_TOKEN=… playground connector-plugin sourcecode -c confluentinc/SalesforceBulkApiV2Sink --only-show-url
# 🌥️  connector plugin confluentinc/SalesforceBulkApiV2Sink was identified as fully managed connector
# ✨ --connector-tag was not set, using latest version on cc-docker-connect (…cache-versions.env) which is <version>
# https://github.com/confluentinc/kafka-connect-salesforce/tree/v<version>
playground connector-plugin fm-versions -c confluentinc/SalesforceBulkApiV2Sink --last 250
# ☁️ confluentinc/SalesforceBulkApiV2Sink (SALESFORCE_CONNECTOR_VERSION) in the last 250 cc-connect versions, newest first
#    0.3730.0 … 0.3785.0  →  3.2.0-rc-4be74dd8-cloud
#    0.3710.0 … 0.3729.0  →  3.2.0-rc-7b0f5ae9-cloud
#    0.3683.0 … 0.3709.0  →  3.2.0-rc-6f27adbb-cloud
#    0.3682.5 … 0.3682.7  →  3.2.0-rc-7b0f5ae9-cloud      <- a rollback
#    …
playground connector-plugin fm-versions -c confluentinc/SalesforceBulkApiV2Sink --last 60 --with-log
# 📜 3.2.0-rc-7b0f5ae9-cloud → 3.2.0-rc-4be74dd8-cloud (cc-connect 0.3729.0 → 0.3730.0)
#    2026-10-14 d2584e88b CC-45809: Fixed the Salesforce Source V2 connector rejecting a valid instance URL when the My Domain enforces SSO. (…)
#    …
playground connector-plugin fm-versions -c confluentinc/S3_SINK --cc-connect-version 0.3780.0
# ☁️ cc-connect 0.3780.0 ships confluentinc/S3_SINK 0.139.0
```

The gotchas of `fm-versions` are in [section 4](/deep-dive-connector-plugin?id=fully-managed-connector-versions-fm-versions).

---

## 7. Recipes for support repros

| Customer question | Command |
| --- | --- |
| "what is this connector, is it supported, how far behind are we?" | `info --from <theirs>` |
| "is this fixed in a newer version?" | `versions --from <theirs>`, `changelog --from <theirs> --grep <symptom>`, then `sourcecode --connector-tag <theirs> --connector-tag <latest> --log --grep <symptom>` and `--files --path <file>` |
| "what changes in our config if we upgrade from X to Y?" | `config-diff --from X --to Y --file <their config>` |
| "since which version does this key exist?" | `config-key --key <k> -c <class> --since-version` |
| "what does this key do, and what's its default in our version?" | `config-key --key <k> -c <class>`; for their exact version, `playground connector show-config-parameters` with `--connector-tag` (adds it to `🗂️ versions run locally`) |
| "this key doesn't work for us" | `config-key`: not in their version (❌ in `versions run locally`), a framework key, or a typo (`💡 similar keys`) |
| "what value do people use?" | the `🧪 values used` part of `config-key`, with one example file per value |
| "our scanner reports CVEs in the connector: are they real, which version fixes them?" | `cve-scan --connector-tag <theirs> --compare-with <latest>` (HTML report to share internally), then `changelog --grep CVE` |
| "our scanner flags jackson / netty 2.x in the connector: which version do we ship, which plugin version upgrades it?" | `dependencies --connector-tag <theirs> --grep <lib>`, then `--find-first <artifact>:<fixed version>` and `changelog --grep <lib>` |
| "`class X is not an instance of Y` / `ClassCastException` when the task starts its producer or consumer" | `search-jar --connector-tag <theirs> --with-worker` (`--class <X>`): a `💥` line means the plugin ships its own copy of a class the worker config (metric reporter, interceptor, login handler) puts in the clients; check that config in their worker properties |
| "NoSuchMethodError / ClassNotFoundException" | `search-jar --class <Class> --connector-tag <theirs> --with-worker`: is the class shipped, with which signature, is the worker's copy used instead (and its signature) |
| "read the code of the version that fails" | `sourcecode --connector-tag <theirs> --checkout-only`, then grep the folder it prints |
| "is the fix of the fully managed connector deployed? which cc-connect image has it?" | `fm-versions -c confluentinc/<Type> --find-first <connector version>` (the image, not the deployment: the cc-connect version of the cluster is in its connect logs) |
| "what changed in the fully managed connector lately?" | `fm-versions -c confluentinc/<Type> --last 50 --with-log` |
| "fully managed connector behaves differently" | `sourcecode -c confluentinc/<Type> --connector-tag <cc-connect version of the cluster>` (`GH_TOKEN` + VPN) |
| "is our bug fixed in a later version? which one?" / "which CVEs are fixed after our version?" | `changelog --from <theirs> --grep "<symptom>\|CVE"`, then the `CC-xxxxx` Jira and the code at that tag |
| "something changed overnight" | `display-last-updated --days 2 --vendor <vendor>` |

---

## 8. Cheat sheet

```bash
playground connector-plugin info -c <owner/name> [--from X] [--max-examples 10] [--json]
playground connector-plugin versions -c <owner/name> [--last N] [--from X] [--latest] [--with-changelog] [--json] [--force-refresh]
playground connector-plugin changelog -c <owner/name> [--from X] [--to Y] [--grep <regex>] [--json]
playground connector-plugin display-last-updated [--days 3] [--vendor <vendor>] [--with-changelog] [--json]
playground connector-plugin config-key -k <key> [-c <class or FM type>] [--max-examples 10] [--since-version] [--json]
playground connector-plugin config-diff -c <owner/name> --from X [--to Y] [--connector-class <class>] [--file <config>] [--with-docs] [--json]
playground connector-plugin sourcecode -c <owner/name> [--connector-tag X [--connector-tag Y]] --only-show-url|--checkout-only
playground connector-plugin sourcecode -c <owner/name> --connector-tag X --grep <regex> | --connector-tag X --connector-tag Y --log [--grep <regex>] | --files [--path <glob>]
playground connector-plugin fm-versions -c confluentinc/<Type> [--last 10] [--with-log] | --cc-connect-version <v> | --find-first <connector version> [--json]
playground connector-plugin search-jar -c <owner/name> [--connector-tag X] | --connector-zip <zip> [--class <Class>] [--with-worker] [--json]
playground connector-plugin cve-scan -c <owner/name> [--connector-tag X] [--compare-with Y] [--severity high] [--json] [--no-open]
playground connector-plugin dependencies -c <owner/name> [--connector-tag X [--connector-tag Y]] [--grep <regex>] [--find-first <artifact>:<version>] [--json]
```

- `-c` / `--connector-plugin`: `owner/name`, a connector class, or a fully managed type; `--json` everywhere.
- `versions` = Hub API, cached one day in `/tmp/version_<owner>_<name>.json` (`--force-refresh` after a release); `--from` = how far behind.
- `changelog` = docs.confluent.io feeds, self-managed Confluent plugins only, `--from` excluded.
- `config-key` = CI references in git + versions run locally. "Since" = CI date, not a version: `--since-version` for the version.
- `config-diff` = the plugin versions themselves (no environment, Docker): added / removed / default changed.
- `sourcecode`: always pass the customer's `--connector-tag`. Scripts: `--only-show-url` / `--checkout-only`, never
  `--open` / `--compile`.
- Fully managed: no `-` in the name, `--connector-tag` = cc-connect image version, `GH_TOKEN` + VPN.
- `search-jar` = the plugin's `lib/`, cached in `/tmp/connector-plugin-jars`; `--with-worker` flags the classes the worker loads instead. Needs Docker and `python3`.
- Sources: [`connector-plugin/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/connector-plugin),
  [`generate-connector-plugin-list.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/generate-connector-plugin-list.sh).

---

**Links**

- 🎬 Video session: [🧑‍💻 The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version)
- 🍪 Deep dives: [`connector create-or-update`](/deep-dive-connector-create-or-update.md) (`diff --defaults` against the
  plugin's defaults), [reproduction models](/deep-dive-reproduction-models.md) (test the fix with `--connector-tag`)
- 🧠 CLI reference: [playground connector-plugin](/playground%20connector-plugin),
  [playground connector-plugin info](/playground%20connector-plugin%20info),
  [playground connector-plugin dependencies](/playground%20connector-plugin%20dependencies),
  [playground connector-plugin cve-scan](/playground%20connector-plugin%20cve-scan),
  [playground connector-plugin fm-versions](/playground%20connector-plugin%20fm-versions),
  [playground connector-plugin config-key](/playground%20connector-plugin%20config-key),
  [playground connector-plugin config-diff](/playground%20connector-plugin%20config-diff),
  [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode),
  [playground connector-plugin versions](/playground%20connector-plugin%20versions),
  [playground connector-plugin changelog](/playground%20connector-plugin%20changelog),
  [playground connector-plugin search-jar](/playground%20connector-plugin%20search-jar)
