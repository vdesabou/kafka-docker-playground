# Debezium Source (Oracle 19c) Source connector

## Objective

Quickly test the [Debezium Oracle](https://debezium.io/documentation/reference/stable/connectors/oracle.html) connector with Oracle 19c (LogMiner).

The connector plugin is downloaded from Maven Central (default version `3.4.1`, override with `--connector-tag`).

## Prerequisites

- Oracle image: the script first tries to download a prebuilt Oracle image from the playground S3 bucket (Confluent employees only, needs AWS credentials). Confluent employees can also check this [link](https://confluent.slack.com/archives/C0116NM415F/p1636391410032900) and [this one](https://confluent.slack.com/archives/C0116NM415F/p1636389483030900).
- Otherwise, download Oracle Database 19c (19.3) for Linux x86-64 `LINUX.X64_193000_db_home.zip` from this [page](https://www.oracle.com/database/technologies/oracle19c-linux-downloads.html) and place it in this folder. The first run builds the docker image `oracle/database:19.3.0-ee` (using this [project](https://github.com/oracle/docker-images/blob/master/OracleDatabase/SingleInstance/README.md)), which takes about 10 minutes. Make sure to increase the Docker disk image size (96 GB is known to work).
- `ojdbc8.jar` must be present in this folder (it must be downloaded manually to acknowledge the Oracle user agreement).

## How to run

```bash
playground run -f debezium-oracle19.sh
```

| Script | Description |
| --- | --- |
| `debezium-oracle19.sh` | Debezium Oracle connector on Oracle 19c CDB `ORCLCDB` |

## What the script does

1. Gets or builds the Oracle 19c image, downloads the Debezium Oracle plugin and adds `ojdbc8.jar` to it.
2. Starts the environment and waits for `DATABASE IS READY TO USE`.
3. Creates a common user `C##MYUSER` with LogMiner privileges and enables supplemental logging.
4. Creates table `CUSTOMERS` (with an update trigger) and inserts 5 rows.
5. Creates the `debezium-oracle-source` connector (`io.debezium.connector.oracle.OracleConnector`, `topic.prefix` `C__MYUSER`).
6. Runs inserts, updates, a delete and an `ALTER TABLE` adding a column.
7. Verifies topics `C__MYUSER.C__MYUSER.CUSTOMERS` (at least 10 records) and `C__MYUSER` (schema changes) with `playground topic consume`.

With `--enable-sql-datagen`, `playground run` injects rows in the `CUSTOMERS` table once the example succeeded, see [Benchmark](#benchmark).

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads rows in the `CUSTOMERS` table for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), with the same database user and container database (CDB or PDB) as the variant of the example that was run. Once the example is running:

```bash
# time to capture 1M rows inserted in one transaction
playground connector benchmark --nb-records 1000000 --shape bulk

# 100k transactions of one row, then 1M updates of existing rows
playground connector benchmark --nb-records 100000 --shape small-txn
playground connector benchmark --nb-records 1000000 --shape update
```

The connector is paused while the rows are loaded, then resumed, and the benchmark measures the time it takes to produce the records.

`playground run -f debezium-oracle19.sh --enable-sql-datagen` uses the same load once the example succeeded: one row per transaction (`--shape small-txn`) from 5 parallel sessions for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION` in minutes), logging the rows inserted every 30 seconds.
