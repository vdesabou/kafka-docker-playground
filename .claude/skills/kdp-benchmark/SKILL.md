---
name: kdp-benchmark
description: |
  Measure or compare connector throughput (and the end-to-end latency of a source) with
  `playground connector benchmark` in kafka-docker-playground — drain or steady mode, load shapes (bulk, small-txn, update, delete),
  several plugin versions (--connector-tag A --connector-tag B), parallel sessions, fully managed
  connectors, and writing or fixing a `benchmark-load.bash` load script (benchmark_sql_load,
  benchmark_python_load, benchmark_files_load…) for a source example or a repro model. Also covers
  `playground run --benchmark` and `playground run --enable-sql-datagen`. Use when asked how fast a
  connector is, whether version Y is slower, what the latency of a source connector is, to
  benchmark / load test a connector, or to add a
  benchmark load to an example.
---

# Benchmark a connector

```bash
playground connector benchmark [--connector <c>]
```

- Drain of `--nb-records` by default; `--mode steady --duration 5m` for a steady rate.
- `--shape bulk|small-txn|update`, `--json`.
- Compares with the previous run in `benchmark-history`.
- Writes an HTML report with the charts to `--output-dir` (opened only in an interactive terminal).
- Records the workers with Java Flight Recorder during the measure and says where the task time went;
  `--no-flight-recorder` to skip it.
- When Grafana runs (`--enable-jmx-grafana`), annotates the measure on its dashboards and links to them.
- When it says the throughput is a lower bound, rerun with 10x `--nb-records`.

## End-to-end latency of a source (steady mode)

- `--mode steady` on a source also measures kafka record timestamp − time of the change in the source
  system, from the records written during the measure (read after it: all up to 100000, else 5 slices of 20000 with
  `topic consume --from-timestamp --max-messages --json`), computed by
  `tools/benchmark-report/benchmark_latency.py`: p50 / p95 / p99 / max in the summary, `latency` in the result
  json, a card over time + histogram + slowest records in the report, and a column in the comparable runs and
  `--connector-tag` tables. It's the number to compare when the summary says the connector kept up with the load.
- Field: `--latency-field <dotted path>` (case insensitive, through avro unions), else the
  `BENCHMARK_LATENCY_FIELD=<field>` line of the load (`benchmark_sql_load`: `create_ts`, `update_ts` with
  `--shape update`, `BENCHMARK_SQL_LATENCY_FIELD` for `custom`), else `source.ts_ms` of a CDC envelope (commit
  time), `__source_ts_ms`, `wallTime` / `clusterTime` of a MongoDB change event. `--no-latency` disables it.
- Not in a drain (the latency is then the time spent in the backlog). Warnings: negative latencies (clock
  skew), a 1 s precision (MySQL `TIMESTAMP` without fsp), and all 0 ms (the connector sets the record
  timestamp from the source). Prefer `--shape small-txn`: a default `CURRENT_TIMESTAMP` is the start of the
  transaction of a whole bulk batch.
- `playground topic consume --plot-latencies-timestamp-field` (gnuplot PNG) no longer exists.

## Comparing versions, shapes, sessions

- `--connector-tag A --connector-tag B [--rounds 2]` benchmarks several plugin versions (update-version,
  version check, warm-up drain, comparison report) and restores the original version.
- `--shape bulk,update,delete` runs one drain per shape on the same rows and compares the phases
  (`benchmark_report.py --group-by shape`). `delete` counts the tombstones from the connector config
  (`tombstones.on.delete`, `emit.tombstone.on.delete`) and is refused for a JDBC source.
- `--sessions <n>` runs the load in n parallel sessions.

## Where the load comes from

**Sinks:** it replays the example's own `playground topic produce` (with `--nb-messages N`). This works for
every sink example that produces its data (148/158 scripts); the Salesforce / SAP HANA ones need
`--load-command`.

**Sources:** the example's `benchmark-load.bash`, or `--load-command` / `--stream-load-command`.

Shipped with the JDBC / Debezium Postgres, Debezium MySQL, JDBC / Debezium SQL Server, Oracle CDC, XStream,
Debezium Oracle, JDBC Oracle, MongoDB, IBM MQ, MQTT (steady only), SQS, Kinesis, Pub/Sub (both connectors),
CloudWatch Logs, SFTP, FTPS, spool dir, FilePulse (CSV), FileStream, HDFS 2 / 3, Debezium MongoDB /
TimescaleDB, JDBC CockroachDB / SingleStore, Lenses ActiveMQ and generalized S3 / GCS / Azure Blob Storage
source examples. The Salesforce Bulk API source example has a load that creates Leads with one Bulk API job.

**Fully managed:** sources whose `ccloud/fm-*` example ships a `benchmark-load.bash` (records counted from the
topic end offsets, no JMX / flight recorder / `--connector-tag`), and sinks (produce replay, records counted
from the committed offsets of `connect-<lcc id>`, which move about once a minute: drains of 10+ commits,
often 1M records). For both, the per minute Metrics API (`sent_records` / `received_records`, put batch time,
batch size, dlq) gives the steady rate of the full minutes. Not supported on cfk.

## Writing a `benchmark-load.bash`

Contract:

- Called with `--records N --mode preload|stream --shape bulk|small-txn|update|delete`, env
  `BENCHMARK_TEST_FILE`, `BENCHMARK_CONNECTOR`, `BENCHMARK_CONNECTOR_CONFIG`.
- Called with `--check` first, before the connector is paused.
- In stream mode it must stop at a batch boundary when `$BENCHMARK_STOP_FILE` exists — killing a producer
  mid-batch sends a truncated record that fails the connector — and print `BENCHMARK_BATCH=<records> <epoch>`
  per batch.
- Optionally print `BENCHMARK_LATENCY_FIELD=<field>` when the records carry the time of the change (for the
  end-to-end latency in steady mode).
- It must source `scripts/cli/src/lib/utils_function.sh`, **not** `scripts/utils.sh` (that one records the
  script as the example being run).

Helpers in `utils_function.sh`:

| Helper | For |
| --- | --- |
| `benchmark_load_args` | parse the arguments above |
| `benchmark_sql_load` | postgres / mysql / oracle `CUSTOMERS` table, sql server `dbo.customers` |
| `benchmark_sql_load custom` + `BENCHMARK_SQL_*` statements | a table of the example |
| `benchmark_mongo_load`, `benchmark_mqtt_load`, `benchmark_ibmmq_load`, `benchmark_activemq_load`, `benchmark_rabbitmq_load`, `benchmark_solace_load`, `benchmark_splunk_load` | the matching systems |
| `benchmark_jms_load` | generic `tools/benchmark-jms/BenchmarkJmsProducer`, compiled once in a JDK container |
| `benchmark_python_load` | SQS / Kinesis / Pub/Sub / CloudWatch Logs with `tools/benchmark-python/benchmark_producer.py`, in an image built once |
| `benchmark_files_load` | files of JSON / CSV / custom rows given to an upload function, e.g. `benchmark_container_files_upload`; `benchmark_users_files_format` for the spool dir family |
| `benchmark_hdfs_load`, `benchmark_cloud_storage_load` | HDFS, S3 / GCS / Azure |
| `benchmark_append_file_load` | FileStream |
| `benchmark_connector_config_value <key>` | read a connector setting: the connect REST API masks passwords (`••••`), the helper then takes them from the example script |
| `benchmark_oracle_client_from_example` | Oracle client settings from the example |

All the database source examples (mysql and mariadb included) use the same `CUSTOMERS` table as
`benchmark_sql_load`.

## Another load script, repro models

- `BENCHMARK_LOAD_SCRIPT=<file>` selects another load script than `benchmark-load.bash` (a file of the
  example's folder, e.g. `benchmark-load-<ticket>.bash` for a repro model; public example
  `connect/connect-jdbc-postgresql-source/postgres-orders.sh` + `benchmark-load-orders.bash`).
- The load script is looked up next to the script that was run. A repro model gets the example's
  `benchmark-load.bash` as a symlink from `repro bootstrap`; to load another table, **replace the symlink
  with a file** (`rm` it first: editing through the link changes the example). See "A table of your own" in
  the docs.

## From `playground run`

- `playground run --benchmark` (also a toggle in the `run` menu) runs `connector benchmark` right after the
  example succeeds, with `BENCHMARK_ARGS` for its flags, and exits with its code if it fails.
- `playground run --enable-sql-datagen` uses the same load: after the example, `sql_datagen_inject` streams
  one-row transactions from `SQL_DATAGEN_SESSIONS` (5) sessions for `SQL_DATAGEN_DURATION` (10) minutes.
  There is no Java datagen nor `sql-datagen` container anymore.
