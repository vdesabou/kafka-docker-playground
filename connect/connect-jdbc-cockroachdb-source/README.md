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

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) inserts rows in the `drivers` table of the example for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark), read by the JDBC source connector in `incrementing` mode on `rownum`. Once the example is running:

```bash
# one statement inserting 100000 rows
playground connector benchmark --nb-records 100000

# 2000 statements of one row, each one its own transaction
playground connector benchmark --nb-records 2000 --shape small-txn

# throughput during 2 minutes while statements of 10000 rows are run
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The `incrementing` mode does not capture updates and deletes, so `--shape update` and `--shape delete` are refused.
