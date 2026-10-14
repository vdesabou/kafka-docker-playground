# JDBC IBM DB2 source connector

## Objective

Quickly test the [JDBC Source](https://docs.confluent.io/kafka-connectors/jdbc/current/source-connector/overview.html) connector with IBM DB2.

## Prerequisites

With CP 8.x, the JDBC connector version must be 10.8.0 or later (the scripts exit with code 111 otherwise).

## How to run

```bash
playground run -f ibmdb2-source.sh
```

| Script | Description |
| --- | --- |
| `ibmdb2-source.sh` | Plain JDBC connection on port 50000 |
| `ibmdb2-source-ssl.sh` | Same, with SSL encryption (DB2 SSL listener on port 50002, truststore mounted in the Connect container) |

## What the script does

1. Starts the `ibmdb2` container first (configured with `SAMPLEDB: "true"`, so the [SAMPLE database](https://www.ibm.com/docs/en/db2/11.5?topic=samples-sample-database) is created) and copies its `db2jcc4.jar` driver into the JDBC connector `lib` folder.
2. Waits for `Setup has completed` in the DB2 logs and for the `sample` database to accept connections.
3. SSL variant only: creates a GSKit key database and self-signed certificate, enables the SSL listener on port 50002 (TLSv1.2), restarts DB2, and imports the server certificate into `security/truststore.jks`.
4. Starts the rest of the environment and lists the tables of the `sample` database.
5. Creates the `ibmdb2-source` connector (`mode=bulk`, `table.whitelist=PURCHASEORDER`, `topic.prefix=db2-`).
6. Verifies that records land in topic `db2-PURCHASEORDER` with `playground topic consume`.
