# 🏎️ Performance

Measure the throughput and the latency of a connector, compare versions, and keep a database busy while you watch. Part of the [🧰 Reproduction toolkit](/reusables.md).

> [!TIP]
> The [🍪 deep dive on connector benchmark](/deep-dive-connector-benchmark.md) explains what exactly is measured, the traps of a local benchmark, and has a hands-on lab.

## 🏎️ Performance testing

[playground connector benchmark](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) is the way to do performance testing with the playground. On a running example or reproduction model, self managed or [fully managed](/toolkit-performance?id=%e2%98%81%ef%b8%8f-fully-managed-connectors), it loads the data, measures the throughput of the connector, tells whether the connector is really the bottleneck, records where its time goes, compares with the previous run or with other versions of the connector, and writes an HTML report to share.

| I want to | Use |
|---|---|
| measure a connector | `playground connector benchmark`: the load comes with the example (the `playground topic produce` of a sink example is replayed, a source example has a `benchmark-load.bash`) |
| compare connector versions | `playground connector benchmark --connector-tag A --connector-tag B` |
| use my own data | [your own load](/toolkit-performance?id=your-own-load) (`--load-command`, or a load script, like the Salesforce source example below) |
| load a table of my own in a reproduction model | [a table of your own](/toolkit-performance?id=a-table-of-your-own-reproduction-models) (`BENCHMARK_LOAD_SCRIPT`) |
| see the broker, the JVM, the connector dashboards | start the example with [JMX Grafana](https://kafka-docker-playground.io/#/how-to-use?id=%f0%9f%93%8a-enabling-jmx-grafana) (`--enable-jmx-grafana`): the benchmark [annotates its measure](/toolkit-performance?id=%f0%9f%93%8a-grafana) |
| benchmark a fully managed connector | run its `ccloud/fm-*` example, keep the connector, then `playground connector benchmark`: see [fully managed connectors](/toolkit-performance?id=%e2%98%81%ef%b8%8f-fully-managed-connectors) |
| keep a database busy while I watch | [`--enable-sql-datagen`](/toolkit-performance?id=%f0%9f%8c%aa%ef%b8%8f-databases-keep-a-load-running-with-enable-sql-datagen) |

### ⏱️ Benchmark a connector

[playground connector benchmark](https://kafka-docker-playground.io/#/playground%20connector%20benchmark) measures the throughput of a running connector, self managed or fully managed, so that you can compare two runs: another `--connector-tag`, another config, another number of tasks, or the numbers of a customer.

<video src="videos/benchmark.mp4" autoplay loop muted playsinline controls width="100%"></video>

By default (`--mode drain`), it pauses the connector, loads a backlog of `--nb-records`, resumes the connector and measures the time it takes to process it. This is the most reproducible number, since it does not depend on how fast the load is generated. `--mode steady` measures the throughput during `--duration` while a load runs in the background.

```bash
# sink: the 'playground topic produce' of the example script is replayed with 3M records
playground connector benchmark --nb-records 3000000

# source: rows inserted in the source database by the benchmark-load.bash of the example
playground connector benchmark --nb-records 1000000 --shape bulk
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update
playground connector benchmark --nb-records 1000000 --shape delete

# insert, update, then delete the same rows: one drain per phase, compared
playground connector benchmark --nb-records 2000000 --shape bulk,update,delete

# throughput during 5 minutes, with a load running in the background
playground connector benchmark --mode steady --duration 5m

# source: the load in 5 parallel sessions (concurrent transactions)
playground connector benchmark --nb-records 1000000 --shape small-txn --sessions 5
```

`--sessions <n>` runs the `benchmark-load.bash` of the example in `n` parallel sessions: a drain splits `--nb-records` between them, steady mode gives each session batches of `--nb-records`. Concurrent transactions are what a busy database looks like to a CDC connector (interleaved transactions in the redo log or the WAL, several open transactions).

The load comes from the example:

* **sink connectors**: the `playground topic produce` of the example script that feeds the connector is replayed with `--nb-messages <n>` (same schema, key and headers), so it works with almost every sink example
* **source connectors**: `benchmark-load.bash` next to the example script, called with `--check` first so that an unsupported combination fails before the connector is paused:
  * JDBC and Debezium PostgreSQL, Debezium MySQL, JDBC and Debezium SQL Server, Oracle CDC, Oracle XStream, Debezium Oracle and JDBC Oracle: rows in the `CUSTOMERS` table (`dbo.customers` for SQL Server), in one transaction (`--shape bulk`), one transaction per row (`--shape small-txn`) as updates (`--shape update`, refused for a JDBC source in `incrementing` mode, which does not capture updates), or as deletes (`--shape delete`, refused for a JDBC source, which does not capture deletes)
  * TimescaleDB (Debezium), CockroachDB and SingleStore (JDBC): rows in the table of the example (the `conditions` hypertable, `drivers`, `application`), `--shape bulk` or `small-txn`
  * MongoDB and Debezium MongoDB: documents in the collection of the connector, with the shape of an existing document so that the schema inferred by the connector stays compatible (`bulk`: insertMany, `small-txn`: insertOne, `update`)
  * IBM MQ (Confluent and ibm-messaging connectors): messages put in the queue of the connector with `amqsput` (the max depth of the queue is raised first)
  * MQTT: messages published with `mosquitto_pub`, **steady mode only**: a paused MQTT source stays subscribed, so the messages published while it is paused go to its in-memory buffer or are dropped by the broker
  * ActiveMQ, WebLogic, TIBCO EMS (and their JMS source variants, Lenses JMS included): messages sent with `BenchmarkJmsProducer` (`tools/benchmark-jms`), a small JMS producer run with the client jars of the broker and the JNDI settings of the connector (`--shape bulk`: transactions of 1000 messages, `--shape small-txn`: one send per message, `BENCHMARK_JMS_JSON=<template>` for JSON messages). A topic destination is measured with `--mode steady` only
  * SQS, Kinesis, Pub/Sub (Confluent and Google connectors) and CloudWatch Logs: messages sent with `tools/benchmark-python/benchmark_producer.py` (boto3, google-cloud-pubsub) in a small image built the first time, in batches (10 messages for SQS, 500 records for Kinesis, 1000 messages for Pub/Sub, 10000 events for CloudWatch Logs), or one per request with `--shape small-txn`
  * RabbitMQ: messages published with the `producer.py` of the example
  * Solace (and JMS Solace): messages sent through the REST messaging port of the broker
  * Splunk: events sent to the HTTP event collector of the connector, **steady mode only** (the connector keeps the events received while it is paused in memory)
  * Files: JSON or CSV files of `BENCHMARK_FILE_RECORDS` records (10000, one record per file with `--shape small-txn`), written so that the connector never reads a file being written: spool dir, SFTP and FTPS (in the format of the connector class and its `input.file.pattern`), FilePulse (CSV rows of `csv.sh`), HDFS 2 and HDFS 3 (Avro files in the layout of the HDFS sink), and the generalized mode of the S3, GCS and Azure Blob Storage sources (names that sort after the files already read). FileStream: lines appended to the file of the connector. The cloud storage and HDFS sources reconfigure their task at each poll interval: the benchmark then counts the records in the topics, and says so
  * Salesforce Bulk API source: Leads created in Salesforce with one Bulk API job (`--shape bulk` drain only, see [the example below](/toolkit-performance?id=a-real-life-example-the-salesforce-bulk-api-source))
* or your own command with `--load-command` (drain) / `--stream-load-command` (steady), for example in a reproduction model (see below)

#### Your own load

Both commands run with `bash -c`, from the current directory. The examples below use a predefined schema of the CLI (`--value @predefined-schemas/avro/customer.avsc`): use the schema of the records your connector expects.

**Drain** (`--load-command`): the command runs while the connector is paused, creates the records and returns. `--nb-records` is the number of records the connector should then process, unless the command prints a line `BENCHMARK_RECORDS=<n>`:

```bash
# sink: 1M records in the topic of the connector
playground connector benchmark --nb-records 1000000 \
  --load-command "playground topic produce -t my-topic --nb-messages 1000000 --value @predefined-schemas/avro/customer.avsc"

# source: your own script, which inserts the rows and prints BENCHMARK_RECORDS=<n>
playground connector benchmark --load-command "./load-my-table.sh 500000"
```

**Steady** (`--stream-load-command`): the command runs in the background. At the end of the measure, the file named by the `BENCHMARK_STOP_FILE` environment variable is created: stop at the end of the current batch when it exists. The command is killed after 120s otherwise, and killing a producer in the middle of a batch can send a truncated record to the topic. Print `BENCHMARK_BATCH=<records> <epoch seconds>` after each batch, so that the summary can tell when the connector only kept up with the load:

```bash
playground connector benchmark --mode steady --duration 2m \
  --stream-load-command 'while [ ! -f "$BENCHMARK_STOP_FILE" ]; do playground topic produce -t my-topic --nb-messages 10000 --value @predefined-schemas/avro/customer.avsc; echo "BENCHMARK_BATCH=10000 $(date +%s)"; done'
```

##### A real-life example: the Salesforce Bulk API source

The [Salesforce Bulk API source example](https://github.com/vdesabou/kafka-docker-playground/tree/master/connect/connect-salesforce-bulkapi-source) reads Leads from a Salesforce org. To benchmark it, the load must create Leads **in Salesforce**, so that the connector picks them up like in production. Creating them one by one (`sfdx data:create:record`) would take one API call per Lead: [its `benchmark-load.bash`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-salesforce-bulkapi-source/benchmark-load.bash) creates them with **one Bulk API job**:

```bash
# the Salesforce user of the connector: the connect REST API shows it (only passwords are masked),
# and the sfdx-cli container of the example is already logged in with it
username=$(benchmark_connector_config_value salesforce.username)

# <records> Leads in one Bulk API job: an upsert on Id with an empty Id inserts every row
awk -v n="$records" -v run="$(date +%s)" 'BEGIN {
  print "Id,FirstName,LastName,Company"
  for (i = 1; i <= n; i++) printf ",Lead%d,benchmark-%s-%d,playground-benchmark\n", i, run, i
}' | playground container exec --container sfdx-cli --command "cat > /tmp/benchmark-leads.csv"
playground container exec --container sfdx-cli --command "sfdx force:data:bulk:upsert --target-org '$username' -s Lead -f /tmp/benchmark-leads.csv -i Id -w 30 --json"

# one record per Lead in the topic of the connector
echo "BENCHMARK_RECORDS=$records"
```

It also deletes the Leads of the previous runs first (a developer org holds about 2500 Leads, 5 MB of data storage), and refuses anything else than a drain with `--shape bulk` in its `--check`. Then:

```bash
playground run -f connect/connect-salesforce-bulkapi-source/salesforce-bulkapi-source.sh
playground connector benchmark --connector salesforce-bulkapi-source --nb-records 1000
```

On a developer org, the 1000 Leads were created in 25 s (one Bulk API job), and the connector wrote them to `sfdc-bulkapi-leads` in 13 s, about 76 records/s. They arrived in bursts, each time a Bulk API query job of the connector completed: with a few thousand Leads, this mostly measures the latency of the query jobs of the org, which is exactly what a customer sees too.

The same pattern works for any source system: create the data **at the source** with its own bulk tools, wait for nothing (the connector is paused), print `BENCHMARK_RECORDS=<n>`.

#### A table of your own (reproduction models)

The loads shipped with the examples always write the `CUSTOMERS` table of the example (`dbo.customers` for SQL Server). When a reproduction model reads another table, the one of the customer for example, give it a load script of its own, **named after its ticket**, next to the reproduction model script, and select it with `BENCHMARK_LOAD_SCRIPT`:

```bash
BENCHMARK_LOAD_SCRIPT=benchmark-load-123456.bash playground connector benchmark --nb-records 500000
```

`BENCHMARK_LOAD_SCRIPT` is a file name in the folder of the script that was run (or an absolute path): several reproduction models of the same folder can each have their load. Without it, the benchmark uses the `benchmark-load.bash` of the folder. `--enable-sql-datagen` uses it too, and the summary and the report work as with the examples: `--check` before the connector is paused, the drain, steady mode, the warnings, plus a warning when the previous run used another load script.

The public example [`connect/connect-jdbc-postgresql-source/postgres-orders.sh`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-jdbc-postgresql-source/postgres-orders.sh) does exactly that: it creates an `orders` table with a JDBC source connector on it, next to `postgres.sh` and the `CUSTOMERS` load of the folder, and its load is [`benchmark-load-orders.bash`](https://github.com/vdesabou/kafka-docker-playground/blob/master/connect/connect-jdbc-postgresql-source/benchmark-load-orders.bash):

```bash
playground run -f connect/connect-jdbc-postgresql-source/postgres-orders.sh
BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --nb-records 1000000
BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --nb-records 100000 --shape small-txn --sessions 4
BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash playground connector benchmark --mode steady --duration 2m --nb-records 2000   # batches of 2000 rows
```

`playground repro bootstrap` links the `benchmark-load.bash` of the example into the folder of the reproduction model, so the `CUSTOMERS` load works out of the box. Don't edit it: it is a link to the file of the example. Write `benchmark-load-<ticket>.bash` instead.

> [!NOTE]
> Reproduction models created before the link existed have no load: link the one of their example (`ln -s ../../connect/<example>/benchmark-load.bash .` in their folder), or write their own.

The load script of `postgres-orders.sh`, a template for yours (copy it as `benchmark-load-<ticket>.bash` and change the table, the SQL and the client):

```bash
#!/bin/bash
# load for 'playground connector benchmark' (BENCHMARK_LOAD_SCRIPT=benchmark-load-orders.bash) and --enable-sql-datagen:
# rows in the orders table of postgres-orders.sh, a table of your own (see "A table of your own" in the documentation)
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# only the functions: sourcing scripts/utils.sh would record this script as the example being run
source ${DIR}/../../scripts/cli/src/lib/utils_function.sh

# --records <n> --mode preload|stream --shape bulk|small-txn|update [--check]
benchmark_load_args "$@"
records="$BENCHMARK_LOAD_RECORDS"

# --check: called before the connector is paused, refuse what this load cannot do
if [ -n "$BENCHMARK_LOAD_CHECK" ]
then
  if [ "$BENCHMARK_LOAD_SHAPE" == "update" ]
  then
    # the connector of postgres-orders.sh is in incrementing mode: it only captures new rows
    logerror "❌ this load only inserts rows (the connector is in incrementing mode): use --shape bulk or small-txn"
    exit 1
  fi
  exit 0
fi

case "$BENCHMARK_LOAD_SHAPE" in
  bulk)
    # one transaction with all the rows
    sql="INSERT INTO orders (customer_id, product, quantity, price) SELECT i % 1000, 'product ' || (i % 50), 1 + i % 5, round((random() * 100)::numeric, 2) FROM generate_series(1, $records) AS i;"
  ;;
  small-txn)
    # one transaction per row
    sql="DO \$\$ BEGIN FOR i IN 1..$records LOOP INSERT INTO orders (customer_id, product, quantity, price) VALUES (i % 1000, 'product ' || (i % 50), 1 + i % 5, round((random() * 100)::numeric, 2)); COMMIT; END LOOP; END \$\$;"
  ;;
esac

function load_batch () {
  echo "$sql" | playground container exec --container postgres --command "psql -U myuser -d postgres" > /dev/null
}

if [ "$BENCHMARK_LOAD_MODE" == "stream" ]
then
  # steady mode: batches of <records> rows until the benchmark creates $BENCHMARK_STOP_FILE
  benchmark_stream_batches "$records" load_batch
else
  # drain: load the backlog, and tell the benchmark how many records the connector should write
  load_batch
  echo "BENCHMARK_RECORDS=$records"
fi
```

What the benchmark expects from the script:

| | |
|---|---|
| arguments | `--records <n> --mode preload\|stream --shape bulk\|small-txn\|update\|delete`, parsed by `benchmark_load_args`, and `--check` first, before the connector is paused: exit with an error for a combination the load cannot do |
| drain (`preload`) | load the rows and return, printing `BENCHMARK_RECORDS=<n>`: the number of records the connector should write (2 per row for Oracle CDC with a redo log topic, for example) |
| steady (`stream`) | repeat batches until the file `$BENCHMARK_STOP_FILE` exists, printing `BENCHMARK_BATCH=<records> <epoch>` after each batch: `benchmark_stream_batches <records> <command>` does both, and never stops a batch in the middle |
| environment | `BENCHMARK_TEST_FILE` (the script that was run: when several reproduction models share the folder, branch on it), `BENCHMARK_CONNECTOR`, `BENCHMARK_CONNECTOR_CONFIG` (a json file with the connector config) |
| source | `scripts/cli/src/lib/utils_function.sh`, not `scripts/utils.sh`, which would record the load script as the example being run |

The same works with MySQL (`mysql -u ... -p...`), Oracle (`sqlplus`, see `benchmark_oracle_client_from_example`) or SQL Server (`sqlcmd`): only the SQL and the client change. For a one-off measure, `--load-command "./load-orders.sh 500000"` (see above) is enough.

#### Is the connector the bottleneck?

A benchmark is only meaningful when the connector is what limits the throughput. The summary and the report warn when it isn't:

| Warning | Meaning |
| --- | --- |
| the connector kept up with the load | steady mode: the load generated about as many records as the connector processed (or the consumer lag of a sink stayed below one sample of records). This is the speed of the load: use `--mode drain`, or compare the end-to-end latency of a source (below) |
| the connector or its tasks were not RUNNING at N status checks | paused, restarting or rebalancing during the measure |
| the connect worker is CPU bound / spent X% of the time in gc pauses | ≥ 90% of the CPUs available to the worker, or > 10% of the time in GC pauses: the result reflects the docker host or the heap size (`KAFKA_HEAP_OPTS`) |
| the records are not spread across the tasks | an idle task, or one task doing most of the work: `tasks.max` greater than the number of partitions, key skew, or a connector that does not parallelize this load |
| N records went to the dead letter queue / were dropped by errors.tolerance=all | failing records are counted in the throughput |
| the load generated N records but the connector processed only M | steady mode: a backlog builds up in the source system, or a publish/subscribe broker (MQTT) drops the messages it cannot deliver |

At the end, it prints a summary (throughput with p50 / p95 / min per sample, put or poll batch time, running ratio, connect CPU), writes the samples (csv) and the result (json, also with `--json`) to `--output-dir`, and opens an HTML report with the charts. Each result is appended to a `benchmark-history` file, and compared with the previous benchmark of the same connector in the same example, mode and shape.

![playground connector benchmark report](./images/report-benchmark.jpg)

#### ⏱️ End-to-end latency of a source

With `--mode steady`, the benchmark of a source connector also measures the end-to-end latency of its records: the Kafka record timestamp minus the time of the change in the source system. After the measure, it reads the records written to the topics of the connector during it (all of them up to 100000, a sample spread over the measure otherwise). It gives p50 / p95 / p99 / max in the summary and the result json. The report shows the latency over time, its distribution and the slowest records, and adds a latency column to the comparable runs and to the `--connector-tag` comparisons. When the connector simply keeps up with the load, this is the number to compare.

```bash
# JDBC source: kafka timestamp - create_ts, the column the load fills with the time of the insert
playground connector benchmark --mode steady --duration 2m --nb-records 1000 --shape small-txn

# another field of the records: a dotted path for a nested one
playground connector benchmark --mode steady --duration 2m --latency-field after.create_ts
```

```
   end-to-end latency     p50 2529.5 ms  p95 4761.0 ms  p99 4916.0 ms  max 4943.0 ms   (create_ts, 33200 records)
```

The field is `--latency-field`, otherwise the field the `benchmark-load.bash` of the example writes the time of the change to (`create_ts` of the `CUSTOMERS` table, `update_ts` with `--shape update`; a load of your own prints `BENCHMARK_LATENCY_FIELD=<field>`), otherwise `source.ts_ms` of a CDC envelope (commit time in the database), or `wallTime` / `clusterTime` of a MongoDB change event. `--no-latency` disables it.

> [!TIP]
> * Use `--shape small-txn`: with `--shape bulk`, a default `CURRENT_TIMESTAMP` is the start of the transaction of the whole batch.
> * The summary warns about negative latencies (the clocks of the source system and of connect are not in sync), a timestamp with a precision of one second (a MySQL `TIMESTAMP` without milliseconds), and latencies that are all 0 ms (the connector sets the record timestamp from the source).
> * It is not measured in a drain: the latency of a record is then the time it waited in the backlog.

#### Insert, update, then delete the same rows

A CDC connector does not handle every change at the same cost: an update carries the before and after images of the row, a delete can also give a tombstone. `--shape` takes a list of shapes: one drain per shape, on the same rows, and the summary and the report compare the phases:

```bash
playground connector benchmark --nb-records 2000000 --shape bulk,update,delete
```

```
   phase  shape   records  seconds  records/s
   1      bulk    2000000  19.1     104712
   2      update  2000000  13.8     144927.5
   3      delete  4000000  19.2     208333.3
```

With Debezium PostgreSQL above, the delete phase has twice as many records: each deleted row gives a delete event and a tombstone. The benchmark reads it from the connector config, so that it waits for the right number of records:

| Connector | Records per deleted row |
|---|---|
| Debezium (PostgreSQL, MySQL, SQL Server, Oracle), Oracle XStream | 2 by default: the delete event and a tombstone (`tombstones.on.delete=true`); 1 with `tombstones.on.delete=false` |
| Oracle CDC | 1, plus a tombstone with `emit.tombstone.on.delete=true` (default `false`) |
| JDBC source | `--shape delete` is refused: a query-based connector does not see deletes |

![playground connector benchmark report comparing the phases of a sequence](./images/report-benchmark-sequence.jpg)

The report shows one bar per phase, the fastest phase, and with the flight recorder, where the time goes by phase (for example, less waiting and more CPU during the updates). A sequence is a series of drains of the load of a source connector: not with `--connector-tag`, `--mode steady` or a sink connector. `--shape delete` alone deletes rows that a previous run inserted (drain only).

#### Compare connector versions

`--connector-tag` (repeat the flag) benchmarks several versions of the connector plugin one after the other. For each version: [playground update-version](https://kafka-docker-playground.io/#/playground%20update-version) `--connector-tag` (only the connect container is restarted, the connector and its offsets are kept), a check that the connector runs the requested version, an untimed warm-up drain (the worker JVM was restarted), then the benchmark. The original version is restored at the end, and the summary and the report compare the versions (one color per version, mean / min / max, delta with the first version). `--rounds 2` alternates the versions (A B A B), which shows a drift from one run to the next:

```bash
playground connector benchmark --nb-records 5000000 --connector-tag 10.9.7 --connector-tag 10.9.9 --rounds 2
```

![playground connector benchmark report comparing connector versions](./images/report-benchmark-versions.jpg)

With the flight recorder (see below), the comparison report also shows where the time goes for each version: CPU by
layer and task time by state, with the change in points, and a finding that names what changed when a version is 5% or
more slower or faster.

![playground connector benchmark report comparing where the time goes by version](./images/report-benchmark-versions-flight-recorder.jpg)

> [!WARNING]
> A downgrade or a major version change can be incompatible with the offsets or the config of the connector: the comparison stops at the first FAILED state.

Each result also records the setup it ran on, shown in the **Setup** section of the report: host (OS, CPU model, CPUs, memory), container engine and the resources given to it, connect image and whether it runs **emulated** (an amd64 image on an arm64 host is much slower), connect JVM and maximum heap, number of workers and brokers, environment, connector plugin version, and the connector configuration with secrets masked. The summary warns when the previous run was on a different setup, and the history chart shows runs of another setup faded. The report also links to the example on GitHub, at the commit it ran with and on the default branch (repro models link to the private repository of the `reproduction-models` submodule), and to the documentation of the connector (from the manifest of its plugin).

#### 🛩️ Where the time goes

The connect workers are recorded with [Java Flight Recorder](/toolkit-debugging?id=%f0%9f%9b%a9%ef%b8%8f-flight-recorder) during the measure (the drain, or the steady measure after the warm-up). The recording runs over JMX: the Confluent images have no `jcmd`, and nothing is restarted. The summary lists the findings, and the report gets a **Where the time goes** section, the same analysis as [`playground analyze flight-recorder`](/playground%20analyze%20flight-recorder): is it the connector, the system behind it, Kafka, a lock? Which part of the pipeline uses the CPU?

```
   flight recorder        🔴 The tasks wait on postgres:5432.
                          ℹ️  Most of the CPU goes to conversion.
                          ℹ️  Allocation is high.
```

![playground connector benchmark report: where the time goes](./images/report-benchmark-flight-recorder.jpg)

The `.jfr` files are kept in `--output-dir`, to open with JDK Mission Control or `playground analyze flight-recorder -f`. The recording costs a few % of throughput: `--no-flight-recorder` disables it, and the summary warns when the previous run was not recorded the same way.

#### 📊 Grafana

When the example runs with [Grafana](/how-to-use?id=%f0%9f%93%8a-enabling-jmx-grafana) (`--enable-jmx-grafana`, also enabled by `--enable-sql-datagen`), the benchmark marks the measure on the dashboards, so that you see the broker side, the JVM and the connector dashboards during the run:

* a region annotation over the window of the measure, with the throughput (`🏎️ benchmark of postgres-source (10.9.9): drain of 3000000 records, 225563.9 records/s`, tags `playground-benchmark`, the connector and its version), on the **Kafka Connect cluster** dashboard, the dashboard of the connector when there is one (**Debezium**, **Oracle CDC**, **Oracle XStream CDC**, **Mongo**), and the **Kafka cluster** dashboard. With `--connector-tag`, each version annotates its own run
* links to those dashboards at the time of the run in the summary and in the header of the HTML report (`📊 Grafana: Kafka Connect cluster · Kafka cluster`)

```
   grafana                http://localhost:3000/d/AEaSQ97mz?orgId=1&from=1792145306949&to=1792145491358
                          measure annotated on 2 dashboard(s): Kafka Connect cluster, Kafka cluster
```

![a playground connector benchmark annotated on the Kafka Connect cluster dashboard](./images/grafana-benchmark-annotation.jpg)

The benchmark does not start Grafana: start the example with it. Prometheus scrapes every 15 s, so a measure needs to last at least 45 s to show on the dashboards; the summary warns when it is shorter (`grafana has only N sample(s) during it`): increase `--nb-records`, or use `--mode steady --duration 2m`. The JMX exporter and the Grafana containers use some CPU: the summary also warns when the previous run was not measured the same way.

#### ☁️ Fully managed connectors

The benchmark also measures the fully managed connectors of the `ccloud/fm-*` examples. Run the example and answer `n` when it asks to delete the connector, then run the benchmark as usual:

```bash
# source: rows in the CUSTOMERS table of the local Postgres, read by the connector through ngrok
playground run -f ccloud/fm-jdbc-postgresql-source/fully-managed-jdbc-postgres-source.sh
playground connector benchmark --nb-records 500000

# sink: the 'playground topic produce' of the example is replayed; 1M records for about 10 offset commits
playground run -f ccloud/fm-jdbc-postgresql-sink/fully-managed-jdbc-postgres-sink.sh
playground connector benchmark --nb-records 1000000 --max-wait 1800
```

The load is the same as for the self managed examples. The 26 `ccloud/fm-*-source` examples that have a self managed equivalent with a benchmark load ship its `benchmark-load.bash`: same local database or broker, reached by the connector through ngrok. A sink replays the `playground topic produce` of its example.

Confluent Cloud gives no JMX, so the records are counted differently:

| | Sources | Sinks |
|---|---|---|
| progress during the measure | end offsets of the topics of the connector, every `--interval` (`kafka.topic`, `topic.prefix`, the topics consumed by the example; `--topic` to choose them) | offsets committed by the consumer group of the connector (`connect-<lcc id>`) |
| resolution | per sample (5 s) | one step per offset commit, about every minute |
| start of a drain | the first records seen after the resume: Confluent Cloud takes 10 to 20 s to restart the tasks | same |

After the measure, the benchmark reads the per minute metrics of the connector in the [Confluent Cloud Metrics API](https://docs.confluent.io/cloud/current/monitoring/metrics-api.html) (`sent_records` / `received_records`). They are exact counts, published about 30 s into each minute. The median of the full minutes of the measure gives the steady throughput, which does not depend on when a sink commits its offsets; a drain needs 3 minutes or more to have a full minute. The put batch time, the batch size and the dead letter queue records come from the same API, and the report shows the records per minute instead of the CPU chart:

```text
🏁 benchmark of 🌤️🤖fully managed connector PostgresSink_vsaboulin (sink, 1 task(s), PostgresSink fully managed, CP ccloud)
   mode                   drain of 971000 records (shape bulk, loaded in 23.9s)
   duration               534.6s
   throughput             1816.3 records/s   (per offset commit, every ~59s: p50 1944.5  p95 2238.5  min 102.8)
   metrics api            2008.3 records/s steady (median of 8 full minute(s) of received_records)
   put batch avg          258.6 ms (450.0 records per batch)
```

For a sink, the end of a drain is only seen at the offset commit that follows it, so the main throughput is conservative by up to one commit interval: the `metrics api` line is the closer figure. A drain that sees less than 5 commits is reported as a lower bound (`≥`), and the summary gives the `--nb-records` of a drain of 10 commits.

> [!NOTE]
> There is no running ratio, cpu, gc, flight recorder nor `--connector-tag` for a fully managed connector: Confluent Cloud runs it, in the version it chooses. The throughput includes the network between the docker host and Confluent Cloud (ngrok tunnel). The Metrics API uses the Cloud API key (`CONFLUENT_CLOUD_API_KEY`) and does not answer for a deleted connector: benchmark before deleting it.

> [!NOTE]
> Everything runs on one docker host: the numbers are relative, compare runs on the same machine only. When the backlog is processed before the first sample, the throughput is only a lower bound (`≥`): increase `--nb-records` 10x. The cfk environment is not supported yet.

### 🌪️ Databases: keep a load running with `--enable-sql-datagen`

For the JDBC, Debezium, Oracle CDC and XStream source examples (Oracle, MySQL, MariaDB, PostgreSQL, SQL Server, self-managed and fully managed), `--enable-sql-datagen` keeps rows coming into the database once the example is done, while you watch the connector (Grafana is enabled with it):

```bash
playground run -f postgres.sh --enable-sql-datagen
SQL_DATAGEN_DURATION=30 SQL_DATAGEN_SESSIONS=10 playground run -f cdc-oracle19-pdb-table.sh --enable-sql-datagen
```

After the example succeeded, `playground run` starts the `benchmark-load.bash` of the example (the load of [playground connector benchmark](/toolkit-performance?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector), on the table its connector reads: `CUSTOMERS` for most examples) in stream mode, one row per transaction, in `SQL_DATAGEN_SESSIONS` parallel sessions (default 5: concurrent transactions, as on a busy database), for `SQL_DATAGEN_DURATION` minutes (default 10). It logs the rows inserted every 30 seconds, then stops the sessions at the end of their current batch:

```
🌪️ injecting rows with benchmark-load.bash for 1 minute(s): 5 session(s), one row per transaction
🌪️ 29500 rows inserted in 31s (951 rows/s)
🌪️ 63000 rows inserted in 61s (1032 rows/s)
🌪️ done: 63600 rows inserted in 61s by 5 session(s)
```

A reproduction model gets the load of its example from `playground repro bootstrap`, and can use a table of its own: see [A table of your own](/toolkit-performance?id=a-table-of-your-own-reproduction-models).

> [!TIP]
> To measure the connector rather than keep it busy, use [playground connector benchmark](/toolkit-performance?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector): same loads, with `--sessions` for parallel sessions.
