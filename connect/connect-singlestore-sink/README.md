# Singlestore sink connector

## Objective

Quickly test the [Singlestore](https://github.com/memsql/singlestore-kafka-connector) sink connector.

## Prerequisites

* The SingleStore JDBC client `singlestore-jdbc-client-1.0.1.jar` is downloaded from Maven Central on the first run and copied into the connector `lib` folder.

## How to run

```bash
playground run -f singlestore-sink.sh
```

## What the script does

1. Starts the environment with a SingleStore container and waits for it to accept queries.
2. Creates the `test` database.
3. Produces 3 Avro records (`{"f1":"value%g"}`) to topic `mytable`.
4. Creates the Singlestore sink connector writing to database `test` on `singlestore:3306`.
5. Queries `select * from mytable` with the `memsql` client and checks the data is present.
