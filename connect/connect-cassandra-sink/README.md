# Cassandra Sink connector

## Objective

Quickly test the [Cassandra Sink](https://docs.confluent.io/kafka-connectors/cassandra/current/overview.html) connector.

Cassandra `3.0` is used.

## Prerequisites

With CP 8.0+, connector version 2.0.11 or later is required when `--connector-tag` is set (the script exits with code `111` otherwise).

## How to run

```bash
playground run -f cassandra-sink.sh
```

| Script | Description |
| --- | --- |
| `cassandra-sink.sh` | Cassandra sink connector writing to keyspace `test` |

## What the script does

1. Starts the environment with a `cassandra` container and waits until `cqlsh` answers.
2. Reads the data center name from `system.local`, required by `cassandra.local.datacenter` with connector 2.0.x (see [Upgrading to version 2.0.x](https://docs.confluent.io/kafka-connectors/cassandra/current/overview.html#upgrading-to-version-2-0-x)).
3. Produces 10 Avro records to topic `topic1` with `playground topic produce`.
4. Creates the Cassandra sink connector (`io.confluent.connect.cassandra.CassandraSinkConnector`), using a `ValueToKey` transform on field `f1` to build the primary key.
5. Queries `test.topic1` with `cqlsh` and verifies the data is there.

Example of results:

```
 f1
---------
  value7
  value9
  value6
  value1
  value8
  value3
  value5
  value4
  value2
 value10

(10 rows)
```
