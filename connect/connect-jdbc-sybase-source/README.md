# JDBC Sybase source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with SAP Sybase ASE 15.7 (`ifnazar/sybase_15_7`), using the jTDS driver.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f sybase-source.sh
```

| Script | Description |
| --- | --- |
| `sybase-source.sh` | JDBC source in `incrementing` mode on a Sybase table |

## What the script does

1. Starts a Sybase container (`dksybase`) alongside the plaintext environment and waits until `isql` can connect. The container runs with `seccomp:unconfined`: under the default seccomp profile of Docker 29, the image's 32-bit `isql` client cannot connect to the server.
2. Creates database `testDB` and table `customers` (identity `id`) with 4 rows.
3. Creates the `jdbc-sybase-source` connector (`jdbc:jtds:sybase://dksybase:5000/testDB`, `mode=incrementing` on `id`, `topic.prefix=sybase-`).
4. Inserts one more row, then verifies that 5 records land in topic `sybase-customers` with `playground topic consume`.
