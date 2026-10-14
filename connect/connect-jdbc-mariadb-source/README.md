# JDBC MariaDB Source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with MariaDB, using the MariaDB JDBC driver (3.2.0).

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f mariadb-jdbc-source.sh
```

| Script | Description |
| --- | --- |
| `mariadb-jdbc-source.sh` | JDBC source in `timestamp+incrementing` mode on a MariaDB table |

## What the script does

1. Downloads `mariadb-java-client-3.2.0.jar` if needed and copies it into the JDBC connector `lib` folder.
2. Starts a MariaDB container alongside the plaintext environment.
3. Creates the `team` table (`id` auto-increment, `last_modified` DATETIME) and inserts 2 rows.
4. Creates the `mariadb-source` connector (`mode=timestamp+incrementing` on `last_modified` / `id`, `topic.prefix=mariadb-`).
5. Verifies that 2 records land in topic `mariadb-team` with `playground topic consume`.
