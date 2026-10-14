# Debezium MariaDB source connector

## Objective

Quickly test the [Debezium MariaDB](https://debezium.io/documentation/reference/3.1/connectors/mariadb.html) connector.

The connector plugin is downloaded from Maven Central (default version `3.0.8`, override with `--connector-tag`, e.g. `--connector-tag 3.1.0`).

## Prerequisites

| Variable | Description |
| --- | --- |
| `SQL_DATAGEN` | Optional: when set, builds the `sql-datagen` tool and injects data for 10 minutes at the end of the run |

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
2. Creates table `team` in database `mydb` and inserts two rows.
3. Creates the `debezium-mariadb-source` connector (`io.debezium.connector.mariadb.MariaDbConnector`) with a `RegexRouter` SMT replacing dots with underscores in topic names.
4. Verifies that topic `server1_mydb_team` contains the 2 records with `playground topic consume`.
5. If `SQL_DATAGEN` is set, injects data for 10 minutes.
