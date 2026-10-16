# Debezium MariaDB source connector

## Objective

Quickly test the [Debezium MariaDB](https://debezium.io/documentation/reference/3.1/connectors/mariadb.html) connector.

The connector plugin is downloaded from Maven Central (default version `3.0.8`, override with `--connector-tag`, e.g. `--connector-tag 3.1.0`).

## Prerequisites

With CP 8.x, the minimal supported connector version is `3.0.0` (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f debezium-mariadb-source.sh
```

| Script | Description |
| --- | --- |
| `debezium-mariadb-source.sh` | Debezium MariaDB connector capturing changes from a MariaDB database |

## What the script does

1. Downloads the Debezium MariaDB connector plugin and starts the environment with a MariaDB container.
2. Creates table `CUSTOMERS` in database `mydb` and inserts two rows.
3. Creates the `debezium-mariadb-source` connector (`io.debezium.connector.mariadb.MariaDbConnector`) with a `RegexRouter` SMT replacing dots with underscores in topic names.
4. Verifies that topic `server1_mydb_CUSTOMERS` contains the 2 records with `playground topic consume`.

With `--enable-sql-datagen` (`playground run -f debezium-mariadb-source.sh --enable-sql-datagen`), once the example succeeded, `playground run` injects rows in the `CUSTOMERS` table of `mydb` with [`benchmark-load.bash`](benchmark-load.bash) (the same load as `playground connector benchmark`) for 10 minutes: one row per transaction, from 5 parallel sessions, logging the rows inserted every 30 seconds. `SQL_DATAGEN_DURATION` (minutes, default `10`) and `SQL_DATAGEN_SESSIONS` (default `5`) change the duration and the number of sessions.
