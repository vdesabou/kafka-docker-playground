# Debezium SQL Server source connector

## Objective

Quickly test the [Debezium SQL Server](https://docs.confluent.io/kafka-connectors/debezium-sqlserver-source/current/overview.html) connector.

## Prerequisites

With CP 8.x, the minimal supported connector version is `2.5.0` (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f debezium-sqlserver-source.sh
```

| Script | Description |
| --- | --- |
| `debezium-sqlserver-source.sh` | Basic example capturing table `dbo.customers` of database `testDB` |
| `debezium-sqlserver-source-ssl.sh` | SQL Server with TLS (self-signed certificate, `database.encrypt=true` with a JKS truststore) |
| `debezium-sqlserver-source-incremental-snapshot.sh` | Ad hoc incremental snapshot of a newly added table, triggered through the signaling table `dbo.debezium_signal` |
| `debezium-sqlserver-source-incremental-snapshot-kafka-signal.sh` | Same, triggered through the Kafka signal topic `dbz-signals` |
| `debezium-sqlserver-source-standalone-worker.sh` | Connector run with `connect-standalone` inside the `connect` container (`standalone-worker/worker.properties` and `connector.properties`), plaintext environment only |

## What the script does

`debezium-sqlserver-source.sh`:

1. Starts the environment with a SQL Server 2019 container.
2. Creates database `testDB`, enables CDC and creates table `customers` with sample rows.
3. Creates the `debezium-sqlserver-source` connector (`io.debezium.connector.sqlserver.SqlServerConnector`, `topic.prefix` `server1`).
4. Inserts one more row.
5. Verifies that topic `server1.testDB.dbo.customers` contains 5 records with `playground topic consume`.

The incremental snapshot variants then add table `customers2`, update the connector to include it, check that only the newly inserted row is captured, send an `execute-snapshot` signal (insert into `debezium_signal` or `playground topic produce` to `dbz-signals`) and verify that all records are in `server1.testDB.dbo.customers2`.

The SSL variant generates a self-signed certificate (`CN=sqlserver`), imports it into a JKS truststore mounted in the `connect` container at `/tmp/truststore.jks`, and configures `database.trustStore` / `database.trustStorePassword`.

With `--enable-sql-datagen`, `playground run` injects rows in the `dbo.customers` table once the example succeeded, see [Benchmark](#benchmark).

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) loads rows in the `dbo.customers` table of the example for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Once the example is running:

```bash
# time to capture 1M rows inserted in one transaction
playground connector benchmark --nb-records 1000000 --shape bulk

# 100k transactions of one row
playground connector benchmark --nb-records 100000 --shape small-txn

# 1M updates of existing rows
playground connector benchmark --nb-records 1000000 --shape update
```

The connector is paused while the rows are loaded, then resumed, and the benchmark measures the time it takes to produce the records.

`playground run -f debezium-sqlserver-source.sh --enable-sql-datagen` uses the same load once the example succeeded: one row per transaction (`--shape small-txn`) from 5 parallel sessions for 10 minutes (`SQL_DATAGEN_SESSIONS`, `SQL_DATAGEN_DURATION` in minutes), logging the rows inserted every 30 seconds.
