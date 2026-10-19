# JDBC Sybase sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with SAP Sybase ASE 15.7 (`ifnazar/sybase_15_7`), using the jTDS driver.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f sybase-sink.sh
```

| Script | Description |
| --- | --- |
| `sybase-sink.sh` | JDBC sink writing Avro records to Sybase with `auto.create=true` |

## What the script does

1. Starts a Sybase container (`dksybase`) alongside the plaintext environment and waits until `isql` can connect. The container runs with `seccomp:unconfined`: under the default seccomp profile of Docker 29, the image's 32-bit `isql` client cannot connect to the server.
2. Creates the `sybase-sink` connector (`jdbc:jtds:sybase://dksybase:5000`, user `sa`, `topics=orders`, `table.name.format=master.dbo.orders`, `auto.create=true`).
3. Produces 2 Avro records (`id`, `product`, `quantity`, `price`) to topic `orders` with `playground topic produce`.
4. Runs `select * from orders` with `isql` and checks that the `foo` row is present.
