# Vertica sink connector

## Objective

Quickly test the [Vertica](https://docs.confluent.io/kafka-connectors/vertica/current/overview.html) sink connector.

## Prerequisites

* With CP 8.x, connector version 1.3.0 or later.
* `vertica-jdbc.jar` is extracted from the Vertica client 10.0.1 package (downloaded from vertica.com) on the first run and copied into the connector `lib` folder.

## How to run

```bash
playground run -f vertica-sink.sh
```

## What the script does

1. Starts a Vertica container and waits for `Vertica is now running`.
2. Produces 10 Avro records (`{"f1":"value%g"}`) to topic `mytable`.
3. Creates the Vertica sink connector writing to database `docker` on `vertica:5433` as `dbadmin`, with `auto.create=true`.
4. Runs `select * from mytable;` with `vsql` in the `vertica` container and checks the rows are present.
