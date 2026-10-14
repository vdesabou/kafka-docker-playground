# JDBC SAP HANA Sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with SAP HANA Express (`saplabs/hanaexpress`), using the SAP HANA JDBC driver (`ngdbc` 2.12.9).

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the script exits with code 111 otherwise).

## How to run

```bash
playground run -f sap-hana-sink.sh
```

| Script | Description |
| --- | --- |
| `sap-hana-sink.sh` | JDBC sink writing Avro records to SAP HANA with `auto.create=true` |

## What the script does

1. Downloads `ngdbc-2.12.9.jar` if needed and copies it into the JDBC connector `lib` folder.
2. Starts SAP HANA Express alongside the plaintext environment and waits for `Startup finished!`.
3. Creates the `LOCALDEV` user (idempotent: in the CFK environment the `post_start` hooks are not mounted).
4. Creates the `jdbc-sap-hana-sink` connector (`jdbc:sap://sap:39041/?databaseName=HXE`, `topics=orders`, String keys, Avro values, `auto.create=true`).
5. Produces 3 Avro records to topic `orders` with `playground topic produce`.
6. Runs `select * from "LOCALDEV"."orders";` with `hdbsql` to verify the data.
