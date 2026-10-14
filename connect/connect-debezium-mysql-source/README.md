# Debezium MySQL source connector

## Objective

Quickly test the [Debezium MySQL](https://docs.confluent.io/kafka-connectors/debezium-mysql-source/current/overview.html) connector.

## Prerequisites

| Variable | Description |
| --- | --- |
| `SQL_DATAGEN` | Optional (`debezium-mysql-source.sh` only): when set, builds the `sql-datagen` tool and injects data for 10 minutes at the end of the run |

With CP 8.x, the minimal supported connector version is `3.0.0` (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f debezium-mysql-source.sh
```

| Script | Description |
| --- | --- |
| `debezium-mysql-source.sh` | Basic example capturing changes from table `mydb.team` |
| `debezium-mysql-source-readonly-inc-snapshot.sh` | Read-only incremental snapshot (`read.only=true`) triggered through a Kafka signal topic, MySQL with GTID mode enabled |

## What the script does

`debezium-mysql-source.sh`:

1. Starts the environment with a MySQL container.
2. Creates table `team` in database `mydb` and inserts two rows.
3. Creates the `debezium-mysql-source` connector with a `RegexRouter` SMT replacing dots with underscores in topic names.
4. Verifies that topic `server1_mydb_team` contains the 2 records with `playground topic consume`.
5. If `SQL_DATAGEN` is set, injects data for 10 minutes.

`debezium-mysql-source-readonly-inc-snapshot.sh`:

1. Starts MySQL with GTID mode on, creates tables `team` and `customers` (two rows each).
2. Creates the connector capturing only `mydb.team`, and verifies topic `server1_mydb_team`.
3. Checks that `GTID_MODE` is `ON`, then updates the connector to also include `mydb.customers` with `read.only=true` and Kafka signal channel `dbz-signals`.
4. Inserts a new customer: only this record shows up in `server1_mydb_customers`.
5. Produces an `execute-snapshot` (`INCREMENTAL`) signal to `dbz-signals` and verifies that all 3 customer records are now in `server1_mydb_customers`.
