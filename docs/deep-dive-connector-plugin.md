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
| every released version, with its release date | `playground connector-plugin versions -c confluentinc/kafka-connect-jdbc` (`--last 5`) |
| what was released on the Hub in the last days | `playground connector-plugin display-last-updated --days 7` (`--vendor confluentinc`) |
| what a config key does, its default, since when, values used | `playground connector-plugin config-key --key batch.size` (`-c JdbcSinkConnector`) |
| the GitHub tree of the code at version X | `playground connector-plugin sourcecode -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --only-show-url` |
| what changed between X and Y | the same with `--connector-tag 10.8.4 --connector-tag 10.9.9` |
| a local checkout of version X, to grep it | `… sourcecode … --connector-tag 10.8.4 --checkout-only` (the folder is the last line) |
| the jars of the plugin, and which one has a class | `playground connector-plugin search-jar -c confluentinc/kafka-connect-s3 --class WebIdentityTokenCredentialsProvider` |

---

## 1. Mental model (the 3 things to remember)

1. **Each answer has its own source, and its own freshness.**

   | Command | Source | Fresh as of |
   | --- | --- | --- |
   | `versions`, `display-last-updated` | Confluent Hub API (`api.hub.confluent.io/api/plugins/<owner>/<name>/versions`) | the first call: cached in `/tmp/version_<owner>_<name>` until `--force-refresh` |
   | `config-key` | the `config-<class>.txt` references next to the examples (about 290 files, tracked in git, refreshed by CI with the latest connector version), plus the versions you ran locally (`.connector_config/`) | your last `git pull` |
   | `sourcecode` | `scripts/cli/confluent-hub-plugin-list.txt` (plugin → repository), built from the Hub on first use; fully managed versions from `cc-docker-connect` | the list: until you regenerate it (`playground generate-connector-plugin-list`) |
   | `search-jar` | the plugin itself, downloaded with `confluent-hub install` in a throw-away container of the connect image | now (needs Docker, not an environment) |

2. **"Since when" is a CI date, not a release note.** `config-key` looks for the commit where the key first appeared
   in the recorded reference of that connector (`git log -S`). CI records the reference with the latest version it
   tests, so that date tells **roughly when a new connector version introduced the key**, not which version. For the
   exact version, run `playground connector show-config-parameters` on two versions (each one is cached in
   `.connector_config/`), or compare the code of the two tags with `sourcecode`.

3. **Self-managed and fully managed resolve versions differently.** A self-managed plugin (`confluentinc/kafka-connect-jdbc`,
   with a `-`) maps a Hub version to a GitHub tag (`v10.8.4`, with per-repository exceptions: Debezium `v<ver>.Final`,
   MongoDB `r<ver>`, Spooldir `kafka-connect-spooldir-<ver>`…). A fully managed one (`confluentinc/SalesforceBulkApiV2Sink`,
   no `-`) has no Hub version: `--connector-tag` is the **cc-connect image version** of the cluster, and the connector
   version is read from `cc-connect/cache-versions.env` of the private `confluentinc/cc-docker-connect` repository at
   that tag. That needs `GH_TOKEN` (or `GITHUB_TOKEN`) and the Confluent VPN. Without `--connector-tag`, the latest
   `cache-versions.env` is used.

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

- **The list is cached, "days ago" included.** The first call writes `/tmp/version_<owner>_<name>` with the lines
  as printed, the number of days computed that day: a week later it still says `36 days ago`, and a release published
  since is missing. Use `--force-refresh` after a release, or before quoting a date.
- Oldest first: `--last N` shows the N most recent, in release order, then the documentation link.
- `display-last-updated` calls `versions --force-refresh` for every self-managed plugin of the list (fully managed ones
  are skipped): it takes minutes. Narrow it with `--vendor`.
- A self-managed `playground run` can compute it in the background (last 3 days, `confluentinc`) and print it at the
  end: off by default, `playground config display-last-updated-connector-plugins true` turns it on,
  `display-last-updated-connector-plugins-days <n>` / `display-last-updated-connector-plugins-vendor <vendor|all>`
  change the window and the vendor (also in the `⚙️ CLI preferences` entry of the `playground run` menu).
- A version without a Hub release date prints `📅 release date: <unknown>`.

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

## 4. Source code: `sourcecode`

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

Gotchas:

- **Scripts and agents: `--only-show-url` or `--checkout-only`, never `--open` / `--compile`.** They open an editor or
  ask questions (an existing folder, recompile?), and wait.
- **Without `--connector-tag`, the latest Hub version** is used (`✨ --connector-tag was not set, using latest version
  on hub 12.1.13`), not the version the customer runs: always pass theirs.
- **The checkout is shallow** (`--depth 1`): `git log` inside has one commit. For history between two versions, use the
  compare URL, or clone the repository yourself.
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

---

## 5. Jars: `search-jar`

```bash
playground connector-plugin search-jar -c confluentinc/kafka-connect-s3 --class WebIdentityTokenCredentialsProvider
playground connector-plugin search-jar -c confluentinc/kafka-connect-s3 --connector-tag 10.5.0 --class WebIdentityTokenCredentialsProvider
```

It installs the plugin (`latest`, or `--connector-tag`) in a throw-away container of the connect image, lists the jars
of its `lib/`, and with `--class` prints the method signatures (`javap`) of every class whose name contains it, with
the jar it's in. Run it on two versions to see when a dependency changed.

Gotchas:

- `--class` is a **case-insensitive substring**: `CredentialsProvider` matches dozens of classes. Give the simple name.
- Needs Docker (not a running environment) and a local `javap` (a JDK).
- It's the plugin's own `lib/`: classes that come from the worker (Kafka, Connect API, the converters of the image) are
  not there. A `NoSuchMethodError` between the plugin and the worker needs both sides: the plugin jar here, the worker
  jar with `playground container exec -c connect --command "ls /usr/share/java/kafka"`.

---

## 6. Hands-on lab (≈10 min, no environment needed)

Steps 1 to 4 need internet access only; step 5 needs Docker; step 6 is for Confluent employees (`GH_TOKEN` + VPN).

**Step 1: versions, and the cache**

```bash
playground connector-plugin versions -c confluentinc/kafka-connect-jdbc --last 3
# 💯 Listing last 3 versions for connector plugin confluentinc/kafka-connect-jdbc
# 🔢 v10.9.7 - 📅 release date: 2026-08-19 (64 days ago)
# 🔢 v10.9.8 - 📅 release date: 2026-09-16 (36 days ago)
# 🔢 v10.9.9 - 📅 release date: 2026-09-16 (36 days ago)
# 🌐 documentation: https://docs.confluent.io/kafka-connect-jdbc/current/
ls -l /tmp/version_confluentinc_kafka-connect-jdbc                                      # the cache
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
grep -rn "BATCH_SIZE_DEFAULT" /tmp/connector-plugin-sourcecode/kafka-connect-jdbc-10.8.4/src/main/java | head -3
# …/sink/JdbcSinkConfig.java:145:  private static final int BATCH_SIZE_DEFAULT = 3000;
```

**Step 5: which jar has a class (Docker)**

```bash
playground connector-plugin search-jar -c confluentinc/kafka-connect-jdbc --connector-tag 10.8.4 --class PostgreSqlDatabaseDialect
# 🔌 Downloading connector plugin confluentinc/kafka-connect-jdbc:10.8.4
# 🤎 Listing jar files: … kafka-connect-jdbc-10.8.4.jar, mssql-jdbc-8.4.1.jre8.jar, ojdbc8-19.7.0.0.jar, postgresql-42.4.4.jar …
# 👉 method signatures from ./kafka-connect-jdbc-10.8.4.jar jar for class io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect
# public class io.confluent.connect.jdbc.dialect.PostgreSqlDatabaseDialect extends io.confluent.connect.jdbc.dialect.GenericDatabaseDialect { …
```

**Step 6 (optional, Confluent employees): a fully managed connector** (not run for this page: the output below is
described from the code)

```bash
GH_TOKEN=… playground connector-plugin sourcecode -c confluentinc/SalesforceBulkApiV2Sink --only-show-url
# 🌥️  connector plugin confluentinc/SalesforceBulkApiV2Sink was identified as fully managed connector
# ✨ --connector-tag was not set, using latest version on cc-docker-connect (…cache-versions.env) which is <version>
# https://github.com/confluentinc/kafka-connect-salesforce/tree/v<version>
```

---

## 7. Recipes for support repros

| Customer question | Command |
| --- | --- |
| "is this fixed in a newer version?" | `versions --last 10`, then `sourcecode --connector-tag <theirs> --connector-tag <latest> --only-show-url` and read the compare (commits, changed files) |
| "what does this key do, and what's its default in our version?" | `config-key --key <k> -c <class>`; for their exact version, `playground connector show-config-parameters` with `--connector-tag` (adds it to `🗂️ versions run locally`) |
| "this key doesn't work for us" | `config-key`: not in their version (❌ in `versions run locally`), a framework key, or a typo (`💡 similar keys`) |
| "what value do people use?" | the `🧪 values used` part of `config-key`, with one example file per value |
| "NoSuchMethodError / ClassNotFoundException" | `search-jar --class <Class> --connector-tag <theirs>`: is the class shipped, with which signature; then the worker side with `container exec` |
| "read the code of the version that fails" | `sourcecode --connector-tag <theirs> --checkout-only`, then grep the folder it prints |
| "fully managed connector behaves differently" | `sourcecode -c confluentinc/<Type> --connector-tag <cc-connect version of the cluster>` (`GH_TOKEN` + VPN) |
| "something changed overnight" | `display-last-updated --days 2 --vendor <vendor>` |

---

## 8. Cheat sheet

```bash
playground connector-plugin versions -c <owner/name> [--last N] [--force-refresh]
playground connector-plugin display-last-updated [--days 3] [--vendor <vendor>]
playground connector-plugin config-key -k <key> [-c <class or FM type>] [--max-examples 10]
playground connector-plugin sourcecode -c <owner/name> [--connector-tag X [--connector-tag Y]] --only-show-url|--checkout-only
playground connector-plugin search-jar -c <owner/name> [--connector-tag X] [--class <Class>]
```

- `versions` = Hub API, cached in `/tmp/version_<owner>_<name>` ("days ago" frozen): `--force-refresh`.
- `config-key` = CI references in git + versions run locally. "Since" = CI date, not a version.
- `sourcecode`: always pass the customer's `--connector-tag`. Scripts: `--only-show-url` / `--checkout-only`, never
  `--open` / `--compile`.
- Fully managed: no `-` in the name, `--connector-tag` = cc-connect image version, `GH_TOKEN` + VPN.
- `search-jar` = the plugin's `lib/` only, needs Docker and `javap`.
- Sources: [`connector-plugin/`](https://github.com/vdesabou/kafka-docker-playground/tree/master/scripts/cli/src/commands/connector-plugin),
  [`generate-connector-plugin-list.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/generate-connector-plugin-list.sh).

---

**Links**

- 🎬 Video session: [🧑‍💻 The source code of a connector at the customer's version](/sessions?id=🧑💻-the-source-code-of-a-connector-at-the-customers-version)
- 🍪 Deep dives: [`connector create-or-update`](/deep-dive-connector-create-or-update.md) (`diff --defaults` against the
  plugin's defaults), [reproduction models](/deep-dive-reproduction-models.md) (test the fix with `--connector-tag`)
- 🧠 CLI reference: [playground connector-plugin](/playground%20connector-plugin),
  [playground connector-plugin config-key](/playground%20connector-plugin%20config-key),
  [playground connector-plugin sourcecode](/playground%20connector-plugin%20sourcecode),
  [playground connector-plugin versions](/playground%20connector-plugin%20versions),
  [playground connector-plugin search-jar](/playground%20connector-plugin%20search-jar)
