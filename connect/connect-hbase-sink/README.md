# HBase Sink connector

## Objective

Quickly test the [HBase Sink](https://docs.confluent.io/kafka-connectors/hbase/current/overview.html) connector.

## Prerequisites

* Not supported with the `cfk` environment.
* With CP 8.3 and later, the connect container is switched to JDK 17 (see [#7862](https://github.com/vdesabou/kafka-docker-playground/issues/7862)).

## How to run

```bash
playground run -f hbase-sink.sh
```

| Script | Description |
| --- | --- |
| `hbase-sink.sh` | Basic example (no security) |
| `hbase-sink-kerberos.sh` | HBase secured with Kerberos. Currently disabled (exits with code 111), see [#6628](https://github.com/vdesabou/kafka-docker-playground/issues/6628#issuecomment-2909737532) |

## What the script does

1. Starts the environment with an HBase container.
2. Produces 3 string records (`value1`..`value3`, keys `key1`..`key3`) to topic `hbase-test`.
3. Creates the `hbase-sink` connector with `auto.create.tables=true` and `table.name.format=example_table`.
4. Runs `scan 'example_table'` in `hbase shell` and checks the 3 rows.

The Kerberos variant additionally creates a `connect` principal and keytab in the KDC, copies the keytab to the connect container and configures `hbase.keytab.file`, `hbase.user.principal` and the master/regionserver principals.
