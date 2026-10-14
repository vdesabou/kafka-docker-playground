# JDBC IBM DB2 sink connector

## Objective

Quickly test the [JDBC Sink](https://docs.confluent.io/kafka-connectors/jdbc/current/sink-connector/overview.html) connector with IBM DB2.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).

## How to run

```bash
playground run -f ibmdb2-sink.sh
```

| Script | Description |
| --- | --- |
| `ibmdb2-sink.sh` | Plain JDBC connection on port 50000 |
| `ibmdb2-sink-ssl.sh` | Same, with SSL encryption (DB2 SSL listener on port 50002, truststore mounted in the Connect container) |

## What the script does

1. Starts the `ibmdb2` container first (configured with `SAMPLEDB: "true"`, so the `sample` database is created) and copies its `db2jcc4.jar` driver into the JDBC connector `lib` folder.
2. Waits for `Setup has completed` in the DB2 logs and for the `sample` database to accept connections.
3. SSL variant only: creates a GSKit key database and self-signed certificate, enables the SSL listener on port 50002, restarts DB2, and imports the server certificate into `security/truststore.jks`.
4. Starts the rest of the environment and produces 2 Avro records (`ID`, `PRODUCT`, `QUANTITY`, `PRICE`) to topic `ORDERS`.
5. Creates the `ibmdb2-sink` connector (`jdbc:db2://ibmdb2:50000/sample`, user `db2inst1`, `auto.create=true`).
6. Runs `db2 select ID,PRODUCT,QUANTITY,PRICE from ORDERS` in the DB2 container and checks that the `foo` row is present.
