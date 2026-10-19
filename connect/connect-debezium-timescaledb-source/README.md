# Debezium PostgreSQL source connector with TimescaleDB

## Objective

Quickly test the [Debezium PostgreSQL](https://docs.confluent.io/kafka-connectors/debezium-postgres-source/current/overview.html) connector with [TimescaleDB](https://debezium.io/documentation/reference/stable/integrations/timescaledb.html), using the Debezium `TimescaleDb` SMT.

## Prerequisites

With CP 8.x, the minimal supported connector version is `2.5.0` (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f debezium-timescaledb-source.sh
```

| Script | Description |
| --- | --- |
| `debezium-timescaledb-source.sh` | Debezium PostgreSQL connector (`pgoutput`) on a TimescaleDB hypertable |

## What the script does

1. Starts the environment with a TimescaleDB container (hypertable `conditions` is created at startup).
2. Creates the `debezium-timescaledb-source` connector capturing schema `_timescaledb_internal`, with Avro converters and the `io.debezium.connector.postgresql.transforms.timescaledb.TimescaleDb` SMT.
3. Inserts a row into `conditions`.
4. Verifies that topic `timescaledb.public.conditions` contains the records with `playground topic consume`.

## Benchmark

[`benchmark-load.bash`](benchmark-load.bash) inserts rows in the `conditions` hypertable of the example (`time`, `location`, `temperature`, `humidity`) for [`playground connector benchmark`](https://kafka-docker-playground.io/#/playground%20connector%20benchmark). Debezium captures them from the chunks of `_timescaledb_internal`, and the `TimescaleDb` transform routes them to `timescaledb.public.conditions`. Once the example is running:

```bash
# one transaction inserting 100000 rows
playground connector benchmark --nb-records 100000

# 5000 transactions of one row
playground connector benchmark --nb-records 5000 --shape small-txn

# throughput during 2 minutes while transactions of 10000 rows are inserted
playground connector benchmark --mode steady --duration 2m --nb-records 10000
```

The hypertable has no key, so `--shape update` and `--shape delete` are not supported.
