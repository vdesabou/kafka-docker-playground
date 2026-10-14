# JDBC MariaDB Sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with MariaDB, using the MariaDB JDBC driver (3.2.0).

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f mariadb-jdbc-sink.sh
```

| Script | Description |
| --- | --- |
| `mariadb-jdbc-sink.sh` | JDBC sink writing Avro records to a MariaDB table |

## What the script does

1. Downloads `mariadb-java-client-3.2.0.jar` if needed and copies it into the JDBC connector `lib` folder.
2. Starts a MariaDB container alongside the plaintext environment.
3. Creates the `mariadb-sink` connector (`jdbc:mariadb://mariadb:3306/db`, `topics=orders`, `auto.create=true`).
4. Produces 2 Avro records to topic `orders` with `playground topic produce`.
5. Describes and selects the `orders` table in MariaDB to verify the data:

```text
id      product quantity        price
1       Norwood 2       0.555599
2       foo     2       0.865833
```
