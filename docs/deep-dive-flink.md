# 🍪 Deep dive: Flink SQL, `playground flink sql`, `list-jobs` and `cancel`

The commands that run Flink SQL next to the playground's Kafka cluster and manage the jobs it submits, without opening
an interactive SQL client or calling the jobmanager REST API by hand: how the Flink cluster is started, what one
`playground flink sql` call does, why a `SELECT` never returns, and how to find and cancel the jobs that keep running.
Takes about 15 minutes to read and run.

| You want | Command |
| --- | --- |
| a Flink cluster next to any example | `playground run -f <example> --enable-flink` (or `ENABLE_FLINK=1`) |
| the Kafka SQL connector (or another one) without the interactive question | `FLINK_URL=<jar url> playground run … --enable-flink` |
| run SQL statements | `playground flink sql << 'EOF' … EOF` / `playground flink sql --file queries.sql` |
| a query that is stopped earlier or later | `… --max-wait 30` (seconds, default `120`) |
| the jobs of the cluster, with the cause of the FAILED ones | `playground flink list-jobs` (`--state RUNNING`) |
| the jobs as data | `playground flink list-jobs --json` |
| cancel a job | `playground flink cancel --job <id>`, `--all`, or no flag when only one job runs |
| the Flink UI | [http://localhost:18081](http://localhost:18081) (same port as the REST API) |
| a ready-made streaming + batch example | `playground run -f flink/flink-sql-kafka/flink-sql-kafka.sh` |

---

## 1. Mental model (the 3 things to remember)

1. **One call = one SQL client session.** `playground flink sql` copies the statements into the `sql-client`
   container and runs `bin/sql-client.sh -f <file>` there, in tableau result mode. The tables live in the default
   in-memory catalog of that session, so **`CREATE TABLE` and the `INSERT INTO` / `SELECT` that uses it go in the same
   call**: a second call doesn't know the tables of the first one. The client stops at the first failing statement,
   and the command exits with code 1.

2. **`INSERT INTO` submits a job and returns, `SELECT` waits for its result.** An `INSERT INTO` becomes a job on the
   cluster (jobmanager + taskmanager): the command prints its id (`🚀 Job <id> submitted`) and returns right away,
   while the job keeps running until it finishes (bounded source) or you cancel it. A `SELECT` prints its rows as a
   table and only returns when the result is complete: on a Kafka or datagen table in streaming mode, **that is
   never**, so the client is stopped after `--max-wait` seconds (exit 1). Use `SET 'execution.runtime-mode' =
   'batch';` with a bounded read (`'scan.bounded.mode' = 'latest-offset'`), or a `LIMIT`.

3. **Connectors are not in the Flink image.** The `flink:${FLINK_TAG}` image only has the built-in connectors
   (`datagen`, `print`, `blackhole`, `filesystem`). Kafka, JDBC, Avro with Schema Registry… are jars downloaded into
   `/opt/flink/lib` **when the containers start**: `--enable-flink` asks which ones, `FLINK_URL` skips the question.
   A missing jar shows up as `Could not find any factory for identifier '<connector>'`, and the fix is to start the
   environment again with the jar, not to retry the statement. The Kafka SQL connector is released for one Flink minor
   version (`flink-sql-connector-kafka-5.0.0-2.2` is for Flink 2.2): pin `FLINK_TAG` with it.

---

## 2. Starting a Flink cluster

`--enable-flink` (or `ENABLE_FLINK=1` in the shell) adds the `flink` docker compose profile to the plaintext
environment, next to the broker:

| Container | Role | Ports on the host |
| --- | --- | --- |
| `jobmanager` | plans the jobs, serves the REST API and the UI | `18081` (REST API + UI), `9091` (Prometheus metrics, with `--enable-jmx-grafana`) |
| `taskmanager` | runs the jobs, 4 task slots | none |
| `sql-client` | the SQL client, configured with the REST address of the jobmanager | none |

```bash
# any example, with Flink and the Kafka SQL connector, no question asked
export FLINK_TAG=2.2
export FLINK_URL="https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/5.0.0-2.2/flink-sql-connector-kafka-5.0.0-2.2.jar"
playground run -f connect/connect-datagen-source/datagen-source.sh --enable-flink   # (any plaintext example)
# 🐿️ Starting services with Flink
# ❗ Downloading connectors from https://repo.maven.apache.org/…, full command executed will be 'wget -P /opt/flink/lib https://repo.maven.apache.org/…'

# or the example that does all of that and runs a streaming and a batch query
playground run -f flink/flink-sql-kafka/flink-sql-kafka.sh
```

From Flink, Kafka is `broker:9092` and Schema Registry `http://schema-registry:8081` (the container names, as for
connectors), not `localhost`.

Gotchas:

- **Plaintext only.** The Flink services are only in `environment/plaintext/docker-compose.yml`: the other
  environments don't start them (cfk prints `⚠️ … is not implemented in environment/cfk/start.sh`), and the
  `flink/flink-sql-kafka` example exits 111 with another environment.
- **`FLINK_TAG` defaults to `latest`.** A Kafka connector jar built for another minor version fails at runtime. The
  example pins `FLINK_TAG=2.2` and `FLINK_KAFKA_CONNECTOR_VERSION=5.0.0-2.2` when `FLINK_TAG` is not set: set both to
  move to another version.
- **`FLINK_URL` takes several jars**, separated by spaces: they are passed to one `wget -P /opt/flink/lib` in the
  entrypoint of the three containers. Without `FLINK_URL`, the interactive question (`❗ Do you need to install any
  Flink connectors? (yes/no)`) needs a terminal: always set it in a script or a repro model.
- **The `playground flink` commands need a running jobmanager**: otherwise they stop with `flink jobmanager rest api
  should be running to run this command: start an example with playground run --enable-flink`.

---

## 3. `playground flink sql`

```bash
# statements on stdin (quote the heredoc delimiter, so that $ and ' survive)
playground flink sql << 'EOF'
CREATE TABLE orders (id INT, product STRING) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
CREATE TABLE sink (id INT, product STRING) WITH ('connector' = 'print');
INSERT INTO sink SELECT * FROM orders;
EOF

# statements in a file, separated by ;
playground flink sql --file ./queries.sql

# a longer query: stop the client after 300 seconds instead of 120
playground flink sql --max-wait 300 --file ./queries.sql
```

What it prints (the JVM warnings and the client banner are removed, each statement is followed by its result):

```bash
# 🐿️ Running Flink SQL statements in sql-client container (Flink 2.2.…, http://localhost:18081)
# Flink SQL> CREATE TABLE orders (…) WITH (…)
# [INFO] Execute statement succeeded.
# Flink SQL> INSERT INTO sink SELECT * FROM orders
# [INFO] Submitting SQL update statement to the cluster...
# [INFO] SQL update statement has been successfully submitted to the cluster:
# Job ID: <id>
# 🚀 Job <id> submitted, follow it with: playground flink list-jobs
```

How it fails, and what the command adds:

| What happens | Exit | What it prints |
| --- | --- | --- |
| no statements (empty stdin, no `--file`) | 1 | `❌ no SQL statements: pass them on stdin (heredoc) or with --file` |
| a statement fails | 1 | the client's `[ERROR] Could not execute SQL statement. Reason:` + exception, then `❌ a Flink SQL statement failed, the next statements were not run` |
| … because a connector or format jar is missing | 1 | the same, plus `the connector or format is not in the Flink image: set FLINK_URL to the jar to download, or answer yes when --enable-flink asks for connectors` |
| the client is still running after `--max-wait` | 1 | `⏱️ the SQL client was stopped after <n>s: a SELECT on an unbounded table never ends in streaming mode`, and what to do (`LIMIT`, batch mode, `--max-wait`, `list-jobs` + `cancel`) |

Gotchas:

- **`SET` only lasts for the call**, like the tables: put `SET 'execution.runtime-mode' = 'batch';`,
  `SET 'parallelism.default' = '2';`, `SET 'restart-strategy.type' = 'none';`… at the top of each call that needs them.
- **The `print` connector writes to the stdout of the taskmanager**, not to the output of the command: read it with
  `playground container logs -c taskmanager --no-follow --tail 50`.
- **A streaming `SELECT` shows a changelog**: the tableau result has an `op` column (`+I` insert, `-U` / `+U` update,
  `-D` delete). In batch mode, only the final rows are printed, followed by `<n> row(s) in set`.
- **The job of a `SELECT` stopped by `--max-wait` may still run on the cluster**: check with
  `playground flink list-jobs --state RUNNING` and cancel it.
- **`sql-client` stopped?** It runs the interactive client as its main process, so quitting a client attached to it
  stops the container. The command then uses the SQL client of the `jobmanager` container instead (it prints
  `… in jobmanager container`): same result.

---

## 4. `playground flink list-jobs` and `playground flink cancel`

```bash
playground flink list-jobs                     # every job, most recent first
playground flink list-jobs --state RUNNING     # INITIALIZING, CREATED, RUNNING, FAILING, FAILED, CANCELLING, CANCELED, FINISHED, RESTARTING, SUSPENDED, RECONCILING
playground flink list-jobs --json | jq -r '.[].jid'   # the /jobs/overview response, as a JSON array, and nothing else

playground flink cancel                        # the running job, when there is only one
playground flink cancel --job <id>             # one job (completion with <tab>)
playground flink cancel --all                  # every job that is not FINISHED, CANCELED or FAILED
```

```bash
playground flink list-jobs
# 📋 Jobs of the Flink cluster (Flink 2.2.…, http://localhost:18081)
# JOB ID                            STATE     NAME                                                          START                DURATION
# <id>                              RUNNING   insert-into_default_catalog.default_database.orders_enriched  2026-10-31 10:20:48  1m22s
```

- The name of a job is the one Flink gives an `INSERT INTO`: `insert-into_<catalog>.<database>.<table>` (cut to 60
  characters), `collect` for a `SELECT`.
- **For each FAILED job, the root cause is printed under the table**: the first line of the exception and its last
  `Caused by:`, because the first line alone is often `Recovery is suppressed by NoRestartBackoffTimeStrategy`. Then
  `🎓 full stack traces: playground container logs -c jobmanager --errors`.
- `cancel` sends the cancel request and **waits until the job is CANCELED (30 seconds at most)**: `✅ Job <id> is
  CANCELED`, or exit 1 when it ends in another state.

Gotchas:

- **`cancel` without a flag refuses to guess**: with several jobs running, it prints `❌ several jobs are running,
  choose one with --job, or cancel them all with --all:` and the running jobs, and exits 1. With none, it prints
  `🤷 no running job to cancel` and exits 0, so `playground flink cancel --all` is safe at the end of a script.
- **A cancelled job doesn't resume where it stopped**: there is no savepoint. A new `INSERT INTO` with the same
  `'properties.group.id'` restarts from the offsets committed to Kafka on checkpoints (there are none unless you
  `SET 'execution.checkpointing.interval' = '10s';`), otherwise from `'scan.startup.mode'`.
- **What the CLI doesn't cover** (savepoints, checkpoints, the job graph, back pressure): use the Flink UI on
  [http://localhost:18081](http://localhost:18081), or the REST API on the same port, for example
  `curl -s http://localhost:18081/jobs/<id>/checkpoints | jq`. There is no `playground` command for those.

---

## 5. Hands-on lab (≈15 min)

Start the plaintext environment with Flink and the Kafka SQL connector, and send 10 JSON orders to a topic (this is
what the beginning of `flink/flink-sql-kafka/flink-sql-kafka.sh` does):

```bash
export FLINK_TAG=2.2
export FLINK_URL="https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/5.0.0-2.2/flink-sql-connector-kafka-5.0.0-2.2.jar"
export ENABLE_FLINK=true
playground start-environment --environment plaintext
playground topic create --topic orders
playground topic create --topic orders-enriched
playground topic produce -t orders --nb-messages 10 << 'EOF'
{
  "type": "record",
  "name": "order",
  "fields": [
    { "name": "id", "type": { "type": "int", "arg.properties": { "iteration": { "start": 1 } } } },
    { "name": "product", "type": { "type": "string", "arg.properties": { "options": ["laptop", "phone", "tablet"] } } },
    { "name": "quantity", "type": { "type": "int", "arg.properties": { "range": { "min": 1, "max": 10 } } } }
  ]
}
EOF
```

**Step 1: a streaming job, from Kafka to Kafka**

```bash
playground flink sql << 'EOF'
CREATE TABLE orders (id INT, product STRING, quantity INT) WITH (
  'connector' = 'kafka', 'topic' = 'orders', 'properties.bootstrap.servers' = 'broker:9092',
  'properties.group.id' = 'flink-orders', 'scan.startup.mode' = 'earliest-offset', 'format' = 'json'
);
CREATE TABLE orders_enriched (id INT, product STRING, quantity INT, price DOUBLE) WITH (
  'connector' = 'kafka', 'topic' = 'orders-enriched', 'properties.bootstrap.servers' = 'broker:9092', 'format' = 'json'
);
INSERT INTO orders_enriched SELECT id, UPPER(product), quantity, quantity * 9.99 FROM orders;
EOF
# 🐿️ Running Flink SQL statements in sql-client container (Flink 2.2.…, http://localhost:18081)
# [INFO] Execute statement succeeded.
# [INFO] SQL update statement has been successfully submitted to the cluster:
# Job ID: <id>
# 🚀 Job <id> submitted, follow it with: playground flink list-jobs
playground topic consume --topic orders-enriched --min-expected-messages 10 --timeout 120
# the 10 orders, with the product in upper case and a price   <- the job runs, and keeps running
```

**Step 2: a batch query, on a bounded read of the same topic**

```bash
playground flink sql << 'EOF'
SET 'execution.runtime-mode' = 'batch';
CREATE TABLE orders (id INT, product STRING, quantity INT) WITH (
  'connector' = 'kafka', 'topic' = 'orders', 'properties.bootstrap.servers' = 'broker:9092',
  'scan.startup.mode' = 'earliest-offset', 'scan.bounded.mode' = 'latest-offset', 'format' = 'json'
);
SELECT COUNT(*) AS nb_orders, SUM(quantity) AS total_quantity FROM orders;
EOF
# +-----------+----------------+
# | nb_orders | total_quantity |
# +-----------+----------------+
# |        10 |             <n> |
# +-----------+----------------+
# 1 row in set                    <- returns: the read stops at the latest offset
```

**Step 3: the jobs of the cluster**

```bash
playground flink list-jobs --state RUNNING
# 📋 Jobs of the Flink cluster (Flink 2.2.…, http://localhost:18081)
# JOB ID  STATE    NAME                                                          START  DURATION
# <id>    RUNNING  insert-into_default_catalog.default_database.orders_enriched  …      …
playground flink list-jobs --json | jq -r '.[] | "\(.jid) \(.state) \(.name)"'
```

The batch query of step 2 is there too with `list-jobs` (no `--state`), as a `FINISHED` `collect` job.

**Step 4: several jobs, and cancelling them**

```bash
playground flink sql << 'EOF'
CREATE TABLE gen (id INT) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
CREATE TABLE nowhere (id INT) WITH ('connector' = 'blackhole');
INSERT INTO nowhere SELECT * FROM gen;
EOF
playground flink cancel
# ❌ several jobs are running, choose one with --job, or cancel them all with --all:      <- exit 1
playground flink cancel --job <id of the nowhere job>
# 🛑 Cancelling job <id> (insert-into_default_catalog.default_database.nowhere)
# ✅ Job <id> is CANCELED
playground flink cancel
# 🛑 Cancelling job <id> (insert-into_default_catalog.default_database.orders_enriched)   <- the only one left
# ✅ Job <id> is CANCELED
playground flink cancel
# 🤷 no running job to cancel                                                             <- exit 0
playground flink list-jobs --state RUNNING
# 🤷 no job in state RUNNING
```

**Step 5: a job that fails at runtime**

```bash
playground flink sql << 'EOF'
SET 'restart-strategy.type' = 'none';
CREATE TABLE words (s STRING) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
CREATE TABLE numbers (n INT) WITH ('connector' = 'blackhole');
INSERT INTO numbers SELECT CAST(s AS INT) FROM words;
EOF
# 🚀 Job <id> submitted, follow it with: playground flink list-jobs       <- submitting works, running doesn't
playground flink list-jobs --state FAILED
# <id>  FAILED  insert-into_default_catalog.default_database.numbers  …
# ❌ job <id> failed with:
# org.apache.flink.runtime.JobException: Recovery is suppressed by NoRestartBackoffTimeStrategy
# Caused by: <the exception of the cast>
# 🎓 full stack traces: playground container logs -c jobmanager --errors
```

Without `'restart-strategy.type' = 'none'`, a job may restart again and again (`RESTARTING`) instead of failing: that
is the customer's "the job never fails, it just doesn't make progress".

**Step 6: the three classic mistakes**

```bash
playground flink sql < /dev/null
# ❌ no SQL statements: pass them on stdin (heredoc) or with --file

playground flink sql << 'EOF'
CREATE TABLE customers (id INT) WITH ('connector' = 'jdbc', 'url' = 'jdbc:postgresql://postgres:5432/postgres', 'table-name' = 'customers');
SELECT * FROM customers;
EOF
# [ERROR] Could not execute SQL statement. Reason:
# org.apache.flink.table.api.ValidationException: Could not find any factory for identifier 'jdbc' …
# ❌ a Flink SQL statement failed, the next statements were not run
#    the connector or format is not in the Flink image: set FLINK_URL to the jar to download, or answer yes when --enable-flink asks for connectors

playground flink sql --max-wait 20 << 'EOF'
CREATE TABLE gen (id INT) WITH ('connector' = 'datagen', 'rows-per-second' = '1');
SELECT * FROM gen;
EOF
# ⏱️ the SQL client was stopped after 20s: a SELECT on an unbounded table never ends in streaming mode
#    add a LIMIT, use SET 'execution.runtime-mode' = 'batch' on a bounded source, or increase --max-wait
#    its job may still run on the cluster: playground flink list-jobs --state RUNNING, then playground flink cancel
playground flink cancel --all     # just in case
```

```bash
playground stop
```

---

## 6. Recipes for support repros

| Customer symptom | Command |
| --- | --- |
| "Flink doesn't read our topic / reads nothing" | the `CREATE TABLE` of the customer with `'properties.bootstrap.servers' = 'broker:9092'`, then a batch `SELECT` with `'scan.bounded.mode' = 'latest-offset'`: an empty result points at `scan.startup.mode`, the topic name or the format |
| "`Could not find any factory for identifier 'kafka'`" | the jar is not in `/opt/flink/lib`: start again with `FLINK_URL=<flink-sql-connector-kafka jar for that Flink minor version>` |
| "the job fails after a few records" | `playground flink list-jobs --state FAILED` (root cause), then `playground container logs -c jobmanager --errors` and `-c taskmanager --errors` |
| "the job never fails but makes no progress" | `list-jobs`: `RESTARTING` again and again; `SET 'restart-strategy.type' = 'none';` to see the error once |
| "bad records in the topic break the job" | `playground topic produce -t <t> --value 'not json' --value-format raw` next to valid records, then the customer's `'json.ignore-parse-errors' = 'true'` or not |
| "Avro records with Schema Registry" | `'format' = 'avro-confluent'`, `'avro-confluent.url' = 'http://schema-registry:8081'`, with the `flink-sql-avro-confluent-registry` jar in `FLINK_URL` |
| "it worked in Flink X, not in Y" | the same statements with `FLINK_TAG=X` then `FLINK_TAG=Y` (and the matching Kafka connector jar) |
| "the job keeps consuming after we stopped the client" | `playground flink list-jobs --state RUNNING`: an `INSERT INTO` (and a `SELECT` stopped by force) runs on the cluster until `playground flink cancel` |

In a repro model, assert on the output instead of reading it:

```bash
output=$(playground flink sql --file "${DIR}/count.sql")
echo "$output" | grep -q -E "^\| +10 \|" || { logerror "❌ the batch query did not count 10 orders"; exit 1; }
[ "$(playground flink list-jobs --json --state FAILED | jq 'length')" == "0" ] || { logerror "❌ a Flink job failed"; exit 1; }
playground flink cancel --all
```

---

## 7. Cheat sheet

```bash
FLINK_TAG=2.2 FLINK_URL="<jar> [<jar>…]" playground run -f <plaintext example> --enable-flink   # or ENABLE_FLINK=1
playground flink sql [--file <file.sql> | << 'EOF' … EOF] [--max-wait 120]
playground flink list-jobs [--state RUNNING|FAILED|…] [--json]
playground flink cancel [--job <id> | --all]
```

- Plaintext only: `jobmanager` (REST API + UI on `18081`), `taskmanager`, `sql-client`. From Flink, Kafka is
  `broker:9092`.
- One call = one SQL client session: `CREATE TABLE` + `INSERT INTO` / `SELECT` together, `SET` at the top.
- `INSERT INTO` = a job that keeps running (`🚀 Job <id> submitted`). Streaming `SELECT` = never ends: batch mode +
  `'scan.bounded.mode'`, or `LIMIT`, or it is stopped after `--max-wait`.
- Connectors = jars in `FLINK_URL`, downloaded when the containers start, built for one Flink minor version.
- `list-jobs` prints the root cause of FAILED jobs. `cancel` waits for CANCELED, refuses to pick between several jobs,
  and is a no-op (exit 0) when nothing runs.
- Sources: [`flink/sql.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/flink/sql.sh),
  [`flink/list-jobs.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/flink/list-jobs.sh),
  [`flink/cancel.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/commands/flink/cancel.sh),
  helpers `get_flink_rest_url` / `filter_flink_running` in
  [`cli_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/cli_function.sh),
  `set_profiles` in [`utils_function.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/cli/src/lib/utils_function.sh),
  [`flink_download_connectors.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/scripts/flink_download_connectors.sh).

---

**Links**

- 👉 Example: [`flink/flink-sql-kafka`](https://github.com/vdesabou/kafka-docker-playground/tree/master/flink/flink-sql-kafka)
- 📖 [Enabling Flink](/how-to-use?id=🐹-enabling-flink) in How to use
- 🍪 Deep dives: [`topic produce`](/deep-dive-topic-produce.md) for the records the jobs read,
  [`topic consume`](/deep-dive-topic-consume.md) to check what they write,
  [`container logs`](/deep-dive-container-logs.md) for the jobmanager and taskmanager logs,
  [running examples and changing versions](/deep-dive-run-and-versions.md) for `--enable-*` flags
- 🧠 CLI reference: [playground flink](/playground%20flink), [playground flink sql](/playground%20flink%20sql),
  [playground flink list-jobs](/playground%20flink%20list-jobs), [playground flink cancel](/playground%20flink%20cancel)
