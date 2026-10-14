# JDBC CockroachDB source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with [CockroachDB](https://www.cockroachlabs.com/), using the PostgreSQL JDBC driver.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f cockroachdb-jdbc.sh
```

| Script | Description |
| --- | --- |
| `cockroachdb-jdbc.sh` | JDBC source in `incrementing` mode on a CockroachDB table |

The CockroachDB DB Console is reachable at [http://127.0.0.1:8080](http://127.0.0.1:8080).

## What the script does

1. Starts a single-node insecure CockroachDB container alongside the plaintext environment.
2. Creates a `drivers` table with a `rownum` column backed by a sequence, and inserts 2 rows.
3. Creates the `cockroachdb-source` connector (`jdbc:postgresql://cockroachdb:26257/defaultdb`, `mode=incrementing` on `rownum`, `topic.prefix=cockroachdb-`).
4. Verifies that 2 records land in topic `cockroachdb-drivers` with `playground topic consume`.
