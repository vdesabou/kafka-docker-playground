# HDFS 2 Source connector

## Objective

Quickly test the [HDFS 2 Source](https://docs.confluent.io/kafka-connectors/hdfs2-source/current/overview.html) connector.

## Prerequisites

* Not supported with the `cfk` environment (exits with code 111).
* Connector versions 2.0.0 and later require CP 6.0.0 or later.
* With CP 8.3 and later, the connect container is switched to JDK 17 (see [#7862](https://github.com/vdesabou/kafka-docker-playground/issues/7862)).

## How to run

```bash
playground run -f hdfs2-source.sh
```

| Script | Description |
| --- | --- |
| `hdfs2-source.sh` | Writes data to HDFS with the HDFS 2 sink connector, then reads it back with the HDFS 2 source connector |

## What the script does

1. Starts the environment with HDFS and Hive containers and opens permissions on `/` in HDFS.
2. Creates an HDFS 2 **sink** connector on topic `hdfs-topic` (`FieldPartitioner` on `f1`, Hive integration) and produces 10 Avro records.
3. Lists `/topics/hdfs-topic` in HDFS, displays one Avro file and checks the Hive table `hdfs_topic` with `beeline`.
4. Creates the `hdfs2-source` connector (`AvroFormat`) with a `RegexRouter` transform that prefixes topic names with `copy-of-`.
5. Verifies that topic `copy-of-hdfs-topic` receives the records with `playground topic consume`.
