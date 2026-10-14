# HDFS 3 Source connector

## Objective

Quickly test the [HDFS 3 Source](https://docs.confluent.io/kafka-connectors/hdfs3-source/current/overview.html) connector.

## Prerequisites

* Not supported with the `cfk` environment (exits with code 111).
* Connector versions 2.0.0 and later require CP 6.0.0 or later.

## How to run

```bash
playground run -f hdfs3-source.sh
```

| Script | Description |
| --- | --- |
| `hdfs3-source.sh` | Writes data to HDFS with the HDFS 3 sink connector, then reads it back with the HDFS 3 source connector |

## What the script does

1. Starts the environment with HDFS (Hadoop 3.1.3) and Hive containers and opens permissions on `/` in HDFS.
2. Creates an HDFS 3 **sink** connector on topic `hdfs-topic` (`FieldPartitioner` on `f1`) and produces 10 Avro records.
3. Lists `/topics/hdfs-topic` in HDFS and displays one Avro file with `playground tools read-avro-file`.
4. Creates the `hdfs3-source` connector (`AvroFormat`) with a `RegexRouter` transform that prefixes topic names with `copy-of-`.
5. Verifies that topic `copy-of-hdfs-topic` receives the records with `playground topic consume`.
