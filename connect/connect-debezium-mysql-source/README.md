# Debezium MySQL source connector

## Objective

Quickly test the [Debezium MySQL](https://docs.confluent.io/kafka-connectors/debezium-mysql-source/current/overview.html) connector.

## Prerequisites

With CP 8.x, the minimal supported connector version is `3.0.0` (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f debezium-mysql-source.sh
```

| Script | Description |
| --- | --- |
| `debezium-mysql-source.sh` | Basic example capturing changes from table `mydb.CUSTOMERS` |
| `debezium-mysql-source-readonly-inc-snapshot.sh` | Read-only incremental snapshot (`read.only=true`) triggered through a Kafka signal topic, MySQL with GTID mode enabled |

## What the script does

`debezium-mysql-source.sh`:

1. Starts the environment with a MySQL container.
2. Creates table `CUSTOMERS` in database `mydb` and inserts two rows.
3. Creates the `debezium-mysql-source` connector with a `RegexRouter` SMT replacing dots with underscores in topic names.
4. Verifies that topic `server1_mydb_CUSTOMERS` contains the 2 records with `playground topic consume`.

`debezium-mysql-source-readonly-inc-snapshot.sh`:

1. Starts MySQL with GTID mode on, creates tables `CUSTOMERS` and `team` (two rows each).
2. Creates the connector capturing only `mydb.CUSTOMERS`, and verifies topic `server1_mydb_CUSTOMERS`.
3. Checks that `GTID_MODE` is `ON`, then updates the connector to also include `mydb.team` with `read.only=true` and Kafka signal channel `dbz-signals`.
4. Inserts a new row in `team`: only this record shows up in `server1_mydb_team`.
5. Produces an `execute-snapshot` (`INCREMENTAL`) signal to `dbz-signals` and verifies that all 3 `team` records are now in `server1_mydb_team`.

With `--enable-sql-datagen`, `playground run` injects rows in the `CUSTOMERS` table once the example succeeded, see [Benchmark](#benchmark).

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads rows in the `CUSTOMERS` table (created if it does not exist) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to capture 1M rows inserted in one transaction
playground connector benchmark --nb-records 1000000 --shape bulk

# 100k transactions of one row, then 1M updates of existing rows
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update

# insert, update, then delete the same 500k rows: one drain per phase, compared in the summary and the report
# each deleted row gives a delete event and a tombstone (tombstones.on.delete, default true)
playground connector benchmark --nb-records 500000 --shape bulk,update,delete

# throughput and end-to-end latency (kafka timestamp - source.ts_ms, the commit time) during 2 minutes while batches of 10k rows are inserted continuously
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The connector is paused while the rows are loaded, then resumed, and the benchmark measures the time it takes to produce the records. Results are compared with the previous benchmark of the same shape.

`playground run -f debezium-mysql-source.sh --enable-sql-datagen` uses the same load once the example succeeded: one row per transaction (`--shape small-txn`) from 5 parallel sessions for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION` in minutes), logging the rows inserted every 30 seconds.
